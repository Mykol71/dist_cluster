#!/usr/bin/env python3
"""Distributed deterministic matrix multiplication over a framed JSON protocol."""

import json
import os
import socket
import struct
import sys
import time
from datetime import datetime, timezone

try:
    from matrix_model import (
        DEFAULT_MATRIX_SEED,
        DEFAULT_MATRIX_SIZE,
        build_matrix_a,
        build_matrix_b,
    )
except ImportError:
    from src.matrix_model import (
        DEFAULT_MATRIX_SEED,
        DEFAULT_MATRIX_SIZE,
        build_matrix_a,
        build_matrix_b,
    )

try:
    import numpy as np
except ImportError:
    np = None


MASTER_ADDR = os.getenv("MASTER_ADDR", "127.0.0.1")
MASTER_PORT = int(os.getenv("MASTER_PORT", "8080"))
WORLD_SIZE = int(os.getenv("WORLD_SIZE", "1"))
RANK = int(os.getenv("RANK", "0"))
BUFFER_SIZE = max(1024, int(os.getenv("BUFFER_SIZE", "1048576")))
MATRIX_SIZE = int(os.getenv("MATRIX_SIZE", str(DEFAULT_MATRIX_SIZE)))
MATRIX_SEED = int(os.getenv("MATRIX_SEED", str(DEFAULT_MATRIX_SEED)))
SOCKET_TIMEOUT = float(os.getenv("CLUSTER_SOCKET_TIMEOUT", "300"))
MAX_FRAME_BYTES = int(os.getenv("MAX_FRAME_BYTES", str(512 * 1024 * 1024)))

OUTPUT_FILENAME = os.getenv("MATRIX_OUTPUT_FILE", "matrix_output.csv")
METRICS_FILENAME = os.getenv("RUN_METRICS_FILE", "run_metrics.json")
FRAME_HEADER = struct.Struct("!Q")


def encode_json(message):
    return json.dumps(
        message,
        allow_nan=False,
        separators=(",", ":"),
    ).encode("utf-8")


def send_frame(sock, payload):
    if len(payload) > MAX_FRAME_BYTES:
        raise ValueError(f"Frame is too large: {len(payload)} bytes")
    sock.sendall(FRAME_HEADER.pack(len(payload)))
    sock.sendall(payload)


def receive_exact(sock, byte_count):
    chunks = []
    remaining = byte_count
    while remaining:
        chunk = sock.recv(min(BUFFER_SIZE, remaining))
        if not chunk:
            raise ConnectionError(
                f"Connection closed with {remaining} framed bytes remaining"
            )
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def receive_frame(sock):
    payload_size = FRAME_HEADER.unpack(receive_exact(sock, FRAME_HEADER.size))[0]
    if payload_size > MAX_FRAME_BYTES:
        raise ValueError(
            f"Peer announced a {payload_size}-byte frame; maximum is {MAX_FRAME_BYTES}"
        )
    return receive_exact(sock, payload_size)


def send_json(sock, message):
    send_frame(sock, encode_json(message))


def receive_json(sock):
    try:
        return json.loads(receive_frame(sock).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("Peer sent an invalid JSON frame") from exc


def row_range(worker_rank, worker_count):
    worker_index = worker_rank - 1
    base_rows, extra_rows = divmod(MATRIX_SIZE, worker_count)
    start_row = worker_index * base_rows + min(worker_index, extra_rows)
    end_row = start_row + base_rows + (1 if worker_index < extra_rows else 0)
    return start_row, end_row


def multiply_chunk(matrix_a_chunk):
    matrix_b = build_matrix_b(MATRIX_SIZE, MATRIX_SEED, np)
    if np is not None:
        return np.asarray(matrix_a_chunk, dtype=np.float64).dot(matrix_b).tolist()

    output = []
    for row in matrix_a_chunk:
        result_row = []
        for column in range(MATRIX_SIZE):
            result_row.append(
                sum(row[k] * matrix_b[k][column] for k in range(MATRIX_SIZE))
            )
        output.append(result_row)
    return output


def write_matrix_output(results):
    if np is not None:
        np.savetxt(
            OUTPUT_FILENAME,
            np.asarray(results, dtype=np.float64),
            delimiter=",",
            fmt="%.10f",
        )
        return

    with open(OUTPUT_FILENAME, "w", encoding="utf-8") as output_file:
        for row in results:
            output_file.write(",".join(f"{value:.10f}" for value in row) + "\n")


def write_run_metrics(network_sec, worker_compute_times, total_sec):
    metrics = {
        "schema_version": 1,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "nodes_count": WORLD_SIZE,
        "worker_count": WORLD_SIZE - 1,
        "matrix_size": MATRIX_SIZE,
        "matrix_seed": MATRIX_SEED,
        "network_sec": network_sec,
        "compute_sec": max(worker_compute_times.values(), default=0.0),
        "total_sec": total_sec,
        "worker_compute_sec": {
            str(rank): duration
            for rank, duration in sorted(worker_compute_times.items())
        },
        "protocol": "length-prefixed-json-v1",
        "output_file": OUTPUT_FILENAME,
    }
    with open(METRICS_FILENAME, "w", encoding="utf-8") as metrics_file:
        json.dump(metrics, metrics_file, indent=2, sort_keys=True)
        metrics_file.write("\n")


def run_master():
    worker_count = WORLD_SIZE - 1
    if worker_count < 1:
        raise ValueError("WORLD_SIZE must include at least one worker")
    if worker_count > MATRIX_SIZE:
        raise ValueError("Worker count cannot exceed MATRIX_SIZE")

    matrix_a = build_matrix_a(MATRIX_SIZE, MATRIX_SEED, np)
    results = [None] * MATRIX_SIZE
    connections = {}
    network_sec = 0.0
    worker_compute_times = {}

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.settimeout(SOCKET_TIMEOUT)
        server.bind((MASTER_ADDR, MASTER_PORT))
        server.listen(worker_count)
        print(f"👑 Master online on {MASTER_ADDR}:{MASTER_PORT}")
        total_start = time.perf_counter()

        try:
            for _ in range(worker_count):
                connection, address = server.accept()
                connection.settimeout(SOCKET_TIMEOUT)
                try:
                    hello = receive_json(connection)
                    worker_rank = int(hello["rank"])
                    if worker_rank < 1 or worker_rank > worker_count:
                        raise ValueError(f"Invalid worker rank {worker_rank}")
                    if worker_rank in connections:
                        raise ValueError(f"Duplicate worker rank {worker_rank}")

                    start_row, end_row = row_range(worker_rank, worker_count)
                    chunk = matrix_a[start_row:end_row]
                    if np is not None:
                        chunk = chunk.tolist()

                    network_start = time.perf_counter()
                    send_json(
                        connection,
                        {
                            "matrix_size": MATRIX_SIZE,
                            "matrix_seed": MATRIX_SEED,
                            "start_row": start_row,
                            "end_row": end_row,
                            "matrix_a_chunk": chunk,
                        },
                    )
                    network_sec += time.perf_counter() - network_start
                    connections[worker_rank] = (
                        connection,
                        address,
                        start_row,
                        end_row,
                    )
                    print(
                        f"📤 Rank {worker_rank}: sent rows "
                        f"{start_row}:{end_row} to {address[0]}"
                    )
                except Exception:
                    connection.close()
                    raise

            for worker_rank in sorted(connections):
                connection, _, start_row, end_row = connections[worker_rank]
                ready = receive_json(connection)
                if int(ready.get("rank", -1)) != worker_rank:
                    raise ValueError(f"Unexpected result rank for worker {worker_rank}")
                compute_sec = float(ready["compute_sec"])

                network_start = time.perf_counter()
                response = receive_json(connection)
                network_sec += time.perf_counter() - network_start
                if int(response.get("rank", -1)) != worker_rank:
                    raise ValueError(f"Result payload rank mismatch for {worker_rank}")

                output_chunk = response["result"]
                expected_rows = end_row - start_row
                if len(output_chunk) != expected_rows:
                    raise ValueError(
                        f"Rank {worker_rank} returned {len(output_chunk)} rows; "
                        f"expected {expected_rows}"
                    )
                if any(len(row) != MATRIX_SIZE for row in output_chunk):
                    raise ValueError(
                        f"Rank {worker_rank} returned a malformed result matrix"
                    )

                results[start_row:end_row] = output_chunk
                worker_compute_times[worker_rank] = compute_sec
                connection.close()
                print(
                    f"📥 Rank {worker_rank}: received {expected_rows} rows "
                    f"(compute {compute_sec:.4f}s)"
                )
        finally:
            for connection, _, _, _ in connections.values():
                connection.close()

    if any(row is None for row in results):
        raise ValueError("Result assembly is incomplete")

    total_sec = time.perf_counter() - total_start
    write_matrix_output(results)
    write_run_metrics(network_sec, worker_compute_times, total_sec)
    print(f"✅ Distributed pipeline finished in {total_sec:.4f} seconds")
    print(f"📂 Matrix saved to '{OUTPUT_FILENAME}'")
    print(f"📊 Runtime metrics saved to '{METRICS_FILENAME}'")


def run_worker():
    if RANK < 1 or RANK >= WORLD_SIZE:
        raise ValueError(f"Worker RANK must be between 1 and {WORLD_SIZE - 1}")

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as worker:
        worker.settimeout(SOCKET_TIMEOUT)
        worker.connect((MASTER_ADDR, MASTER_PORT))
        send_json(worker, {"rank": RANK})
        request = receive_json(worker)

        if int(request["matrix_size"]) != MATRIX_SIZE:
            raise ValueError("Master and worker MATRIX_SIZE values do not match")
        if int(request["matrix_seed"]) != MATRIX_SEED:
            raise ValueError("Master and worker MATRIX_SEED values do not match")

        matrix_a_chunk = request["matrix_a_chunk"]
        expected_rows = int(request["end_row"]) - int(request["start_row"])
        if len(matrix_a_chunk) != expected_rows:
            raise ValueError("Master sent a malformed matrix chunk")

        print(f"📥 Rank {RANK}: received {expected_rows} deterministic rows")
        compute_start = time.perf_counter()
        output_chunk = multiply_chunk(matrix_a_chunk)
        compute_sec = time.perf_counter() - compute_start
        print(f"⚡ Rank {RANK}: computation took {compute_sec:.4f} seconds")

        send_json(worker, {"rank": RANK, "compute_sec": compute_sec})
        send_json(worker, {"rank": RANK, "result": output_chunk})


def main():
    print(f"🔹 Rank {RANK} initialization complete")
    if RANK == 0:
        run_master()
    else:
        run_worker()


if __name__ == "__main__":
    try:
        main()
    except (ConnectionError, KeyError, OSError, TypeError, ValueError) as exc:
        print(f"❌ Rank {RANK} failed: {exc}", file=sys.stderr)
        sys.exit(1)
