#!/usr/bin/env python3
"""A small, dependency-light distributed matrix multiplication demo.

Rank 0 assigns contiguous row ranges to worker ranks over TCP.  Messages use a
length prefix and NumPy's non-pickle ``.npy`` representation, avoiding the
ambiguous packet-boundary and ``eval`` protocol used by the original prototype.
"""

from __future__ import annotations

import io
import json
import os
import socket
import struct
import sys
import time

try:
    import numpy as np
except ImportError:
    np = None


MASTER_ADDR = os.getenv("MASTER_ADDR", "127.0.0.1")
MASTER_PORT = int(os.getenv("MASTER_PORT", "8080"))
WORLD_SIZE = int(os.getenv("WORLD_SIZE", "1"))
RANK = int(os.getenv("RANK", "0"))
MATRIX_SIZE = int(os.getenv("MATRIX_SIZE", "600"))
BUFFER_SIZE = int(os.getenv("BUFFER_SIZE", str(1024 * 1024)))
CONNECT_TIMEOUT = float(os.getenv("CONNECT_TIMEOUT", "30"))
MAX_MESSAGE_BYTES = int(os.getenv("MAX_MESSAGE_BYTES", str(512 * 1024 * 1024)))
OUTPUT_FILENAME = os.getenv("OUTPUT_FILENAME", "matrix_output.csv")
METRICS_FILENAME = os.getenv("METRICS_FILENAME", "cluster_metrics.json")


def send_message(sock: socket.socket, payload: bytes) -> None:
    if len(payload) > MAX_MESSAGE_BYTES:
        raise ValueError("message exceeds configured size limit")
    sock.sendall(struct.pack("!Q", len(payload)) + payload)


def receive_exact(sock: socket.socket, size: int) -> bytes:
    chunks: list[bytes] = []
    remaining = size
    while remaining:
        chunk = sock.recv(min(remaining, BUFFER_SIZE))
        if not chunk:
            raise ConnectionError("connection closed before a complete message arrived")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def receive_message(sock: socket.socket) -> bytes:
    size = struct.unpack("!Q", receive_exact(sock, 8))[0]
    if size > MAX_MESSAGE_BYTES:
        raise ValueError(f"peer advertised an oversized message ({size} bytes)")
    return receive_exact(sock, size)


def encode_array(array) -> bytes:
    if np is None:
        return json.dumps(array).encode("utf-8")
    stream = io.BytesIO()
    np.save(stream, array, allow_pickle=False)
    return stream.getvalue()


def decode_array(payload: bytes):
    if np is None:
        return json.loads(payload.decode("utf-8"))
    return np.load(io.BytesIO(payload), allow_pickle=False)


def connect_to_master() -> socket.socket:
    deadline = time.monotonic() + CONNECT_TIMEOUT
    last_error: OSError | None = None
    while time.monotonic() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(min(5, max(1, deadline - time.monotonic())))
        try:
            sock.connect((MASTER_ADDR, MASTER_PORT))
            sock.settimeout(None)
            return sock
        except OSError as error:
            last_error = error
            sock.close()
            time.sleep(0.25)
    raise ConnectionError(f"could not connect to {MASTER_ADDR}:{MASTER_PORT}") from last_error


def run_master() -> None:
    if WORLD_SIZE < 2:
        raise ValueError("WORLD_SIZE must include rank 0 and at least one worker")
    if np is None:
        raise RuntimeError("NumPy is required on the master for this workload")

    worker_count = WORLD_SIZE - 1
    rng = np.random.default_rng(2026)
    matrix_a = rng.random((MATRIX_SIZE, MATRIX_SIZE))
    total_start = time.perf_counter()

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((MASTER_ADDR, MASTER_PORT))
    server.listen(worker_count)
    print(f"Master listening on {MASTER_ADDR}:{MASTER_PORT} for {worker_count} worker(s).")

    connections: dict[int, socket.socket] = {}
    try:
        while len(connections) < worker_count:
            connection, address = server.accept()
            rank = int(receive_message(connection).decode("ascii"))
            if rank < 1 or rank > worker_count or rank in connections:
                connection.close()
                raise ValueError(f"invalid or duplicate worker rank {rank} from {address}")
            connections[rank] = connection
            print(f"Worker rank {rank} connected from {address[0]}.")

        row_ranges: dict[int, tuple[int, int]] = {}
        for rank, connection in connections.items():
            start = (rank - 1) * MATRIX_SIZE // worker_count
            end = rank * MATRIX_SIZE // worker_count
            row_ranges[rank] = (start, end)
            metadata = json.dumps({"start": start, "end": end}).encode("utf-8")
            send_message(connection, metadata)
            send_message(connection, encode_array(matrix_a[start:end]))

        results = np.empty((MATRIX_SIZE, MATRIX_SIZE))
        network_seconds = 0.0
        compute_seconds = 0.0
        for rank, connection in connections.items():
            receive_start = time.perf_counter()
            metadata = json.loads(receive_message(connection).decode("utf-8"))
            output = decode_array(receive_message(connection))
            network_seconds += time.perf_counter() - receive_start
            start, end = row_ranges[rank]
            if metadata.get("start") != start or metadata.get("end") != end:
                raise ValueError(f"worker {rank} returned an unexpected row range")
            if output.shape != (end - start, MATRIX_SIZE):
                raise ValueError(f"worker {rank} returned an unexpected output shape {output.shape}")
            results[start:end] = output
            compute_seconds = max(compute_seconds, float(metadata["compute_seconds"]))
            print(f"Received rows {start}:{end} from worker rank {rank}.")

        np.savetxt(OUTPUT_FILENAME, results, delimiter=",", fmt="%.4f")
        total_seconds = time.perf_counter() - total_start
        with open(METRICS_FILENAME, "w", encoding="utf-8") as metrics_file:
            json.dump({"network_seconds": network_seconds, "compute_seconds": compute_seconds,
                       "total_seconds": total_seconds}, metrics_file)
        print(f"Completed in {total_seconds:.4f}s; wrote {OUTPUT_FILENAME}.")
    finally:
        for connection in connections.values():
            connection.close()
        server.close()


def run_worker() -> None:
    if np is None:
        raise RuntimeError("NumPy is required on workers for this workload")
    with connect_to_master() as worker:
        send_message(worker, str(RANK).encode("ascii"))
        assignment = json.loads(receive_message(worker).decode("utf-8"))
        matrix_chunk = decode_array(receive_message(worker))
        matrix_b = np.random.default_rng(2027).random((MATRIX_SIZE, MATRIX_SIZE))
        compute_start = time.perf_counter()
        output = matrix_chunk @ matrix_b
        compute_seconds = time.perf_counter() - compute_start
        metadata = json.dumps({**assignment, "compute_seconds": compute_seconds}).encode("utf-8")
        send_message(worker, metadata)
        send_message(worker, encode_array(output))
        print(f"Rank {RANK} completed rows {assignment['start']}:{assignment['end']} in {compute_seconds:.4f}s.")


if __name__ == "__main__":
    try:
        if BUFFER_SIZE < 1:
            raise ValueError("BUFFER_SIZE must be positive")
        if RANK == 0:
            run_master()
        else:
            run_worker()
    except (ConnectionError, OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"Cluster rank {RANK} failed: {error}", file=sys.stderr)
        sys.exit(1)
