import os
import socket
import sys
import time

# 1. PARSE BASH CLUSTER CONFIGURATION
MASTER_ADDR = os.getenv("MASTER_ADDR", "127.0.0.1")
MASTER_PORT = int(os.getenv("MASTER_PORT", "8080"))
WORLD_SIZE = int(os.getenv("WORLD_SIZE", "1"))
RANK = int(os.getenv("RANK", "0"))

# OPTIMIZED NETWORK CHUNK SIZE: 1MB buffer for fast internet streaming
BUFFER_SIZE = 1048576

print(f"🔹 [Node Rank {RANK}] Worker initialization complete.")

try:
import numpy as np
USE_NUMPY = True
except ImportError:
USE_NUMPY = False

MATRIX_SIZE = 600

def fallback_matrix_multiply(row, size):
mock_matrix = [[i * 0.01 for i in range(size)] for _ in range(size)]
result_row = [0.0] * size
for col in range(size):
dot_product = 0.0
for k in range(size):
dot_product += row[k] * mock_matrix[k][col]
result_row[col] = dot_product
return result_row

# 3. NETWORKING ENGINE: MASTER VS WORKER LOGIC
if RANK == 0:
# --- MASTER NODE LOGIC ---
print(f"👑 Master Node online on {MASTER_ADDR}:{MASTER_PORT}...")
if USE_NUMPY:
matrix_A = np.random.rand(MATRIX_SIZE, MATRIX_SIZE)
else:
matrix_A = [[i * 0.05 for i in range(MATRIX_SIZE)] for _ in range(MATRIX_SIZE)]

worker_count = WORLD_SIZE - 1
if worker_count == 0:
print("❌ Error: No iPhone nodes running.")
sys.exit(1)
rows_per_worker = MATRIX_SIZE // worker_count

server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_socket.bind((MASTER_ADDR, MASTER_PORT))
server_socket.listen(worker_count)

# ⏱️ START TOTAL TIMERS (Wall-clock time)
total_start_time = time.perf_counter()
results = [None] * MATRIX_SIZE

for i in range(worker_count):
conn, addr = server_socket.accept()
worker_rank = int(conn.recv(1024).decode())
start_row = (worker_rank - 1) * rows_per_worker
end_row = MATRIX_SIZE if worker_rank == worker_count else start_row + rows_per_worker
if USE_NUMPY:
chunk = matrix_A[start_row:end_row].tolist()
else:
chunk = matrix_A[start_row:end_row]
conn.sendall(repr(chunk).encode())
# 📥 RECEIVE LOOP WITH OPTIMIZED CHUNK SIZE & REAL-TIME TRANSFER TIMER
net_start_time = time.perf_counter()
data_buffer = b""
print(f"📥 Downloading results from [Rank {worker_rank}] using 1MB streams...")
while True:
# Using the optimized 1MB chunk size buffer limit
packet = conn.recv(BUFFER_SIZE)
if not packet: break
data_buffer += packet
sys.stdout.write("▓")
sys.stdout.flush()
net_end_time = time.perf_counter()
net_duration = net_end_time - net_start_time
# Calculate download speeds dynamically
data_size_kb = len(data_buffer) / 1024.0
sys.stdout.write(f" Done! Received {data_size_kb:.2f} KB in {net_duration:.4f} seconds.\n")
processed_chunk = eval(data_buffer.decode())
results[start_row:end_row] = processed_chunk
conn.close()

total_duration = time.perf_counter() - total_start_time
print(f"✅ Success! Distributed pipeline finished in {total_duration:.4f} seconds.")
server_socket.close()

# --- SAVE FILE ENGINE ---
output_filename = "matrix_output.csv"
if USE_NUMPY:
np.savetxt(output_filename, np.array(results), delimiter=",", fmt="%.4f")
else:
with open(output_filename, "w") as f:
for row in results:
f.write(",".join(f"{val:.4f}" for val in row) + "\n")
print(f"📂 Saved to '{output_filename}'")

else:
# --- IPHONE WORKER NODE LOGIC ---
time.sleep(1)
worker_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
worker_socket.connect((MASTER_ADDR, MASTER_PORT))
except Exception as e:
sys.exit(1)

worker_socket.sendall(str(RANK).encode())

# Worker receive block using optimized 1MB buffer
data_buffer = b""
while True:
packet = worker_socket.recv(BUFFER_SIZE)
if b']' in packet and packet.endswith(b']'):
data_buffer += packet
break
if not packet: break
data_buffer += packet

matrix_chunk = eval(data_buffer.decode())
print(f"📥 [Rank {RANK}] Data parsed into physical memory.")

# ⏱️ TIME THE HARDWARE COMPUTATION FOOTPRINT (Excludes network latency)
compute_start = time.perf_counter()
output_chunk = []
if USE_NUMPY:
mock_b = np.random.rand(MATRIX_SIZE, MATRIX_SIZE)
output_chunk = np.array(matrix_chunk).dot(mock_b).tolist()
else:
for row in matrix_chunk:
output_chunk.append(fallback_matrix_multiply(row, MATRIX_SIZE))
compute_duration = time.perf_counter() - compute_start
print(f"⚡ [Rank {RANK}] VRAM/RAM hardware computation took exactly {compute_duration:.4f} seconds!")

# Return data to Master Node
worker_socket.sendall(repr(output_chunk).encode())
worker_socket.close()
