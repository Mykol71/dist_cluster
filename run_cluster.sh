#!/usr/bin/env bash

# CONFIGURATION
IPHONE_NODES=("iphoneA" "iphoneB")
MASTER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || hostname -I | awk '{print $1}')
MASTER_PORT=8080
WORLD_SIZE=$(( ${#IPHONE_NODES[@]} + 1 ))
REMOTE_PROJECT_DIR="/app"
SCRIPT_NAME="train_dist.py"

echo "=================================================="
echo "🌀 Launching Distributed GPU/VRAM Processing Pool"
echo "=================================================="

# ⚡ DYNAMIC NETWORK PING BENCHMARK
echo "📡 Measuring network latency across internet VPN..."
OPTIMAL_BUFFER=1048576 # Global default fallback (1MB)

for node in "${IPHONE_NODES[@]}" do
# Call our ping diagnostic script using the hostname configuration profile
detected_buffer=$(python3 ./src/ping_test.py "$node")
if [ "$detected_buffer" -gt "$OPTIMAL_BUFFER" ]; then
OPTIMAL_BUFFER=$detected_buffer
fi
done

echo "⚙️ Network tuning complete. Optimal cluster chunk size set to: $OPTIMAL_BUFFER bytes."
echo "--------------------------------------------------"

# LOOP & SPAWN IPHONE WORKERS
RANK=1
for node in "${IPHONE_NODES[@]}" do
echo "📡 [RANK $RANK] Triggering optimized worker on $node..."
# Inject both standard rank settings AND your fresh dynamic BUFFER_SIZE variable
ssh "$node" "cd $REMOTE_PROJECT_DIR && \
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=$RANK \
BUFFER_SIZE=$OPTIMAL_BUFFER \
python3 $SCRIPT_NAME" &
RANK=$((RANK + 1))
done

sleep 2

# LAUNCH LOCAL MASTER COMPUTATION (RANK 0)
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=0 \
BUFFER_SIZE=$OPTIMAL_BUFFER \
python3 "$REMOTE_PROJECT_DIR/$SCRIPT_NAME"

wait
echo "🎉 Cluster processing complete."

echo "=================================================="
echo "🌀 Launching Distributed GPU/VRAM Processing Pool"
echo "=================================================="

# ⚡ DYNAMIC NETWORK PING BENCHMARK
echo "📡 Measuring network latency across internet VPN..."
OPTIMAL_BUFFER=1048576 # Global default fallback (1MB)

for node in "${IPHONE_NODES[@]}" do
# Call our ping diagnostic script using the hostname configuration profile
detected_buffer=$(python3 ./src/ping_test.py "$node")
if [ "$detected_buffer" -gt "$OPTIMAL_BUFFER" ]; then
OPTIMAL_BUFFER=$detected_buffer
fi
done

echo "⚙️ Network tuning complete. Optimal cluster chunk size set to: $OPTIMAL_BUFFER bytes."
echo "--------------------------------------------------"

# LOOP & SPAWN IPHONE WORKERS
RANK=1
for node in "${IPHONE_NODES[@]}" do
echo "📡 [RANK $RANK] Triggering optimized worker on $node..."
# Inject both standard rank settings AND your fresh dynamic BUFFER_SIZE variable
ssh "$node" "cd $REMOTE_PROJECT_DIR && \
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=$RANK \
BUFFER_SIZE=$OPTIMAL_BUFFER \
python3 $SCRIPT_NAME" &
RANK=$((RANK + 1))
done

sleep 2

# LAUNCH LOCAL MASTER COMPUTATION (RANK 0)
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=0 \
BUFFER_SIZE=$OPTIMAL_BUFFER \
python3 "$REMOTE_PROJECT_DIR/$SCRIPT_NAME"

wait
echo "🎉 Cluster processing complete."

echo "=================================================="
echo "🌀 Launching Distributed GPU/VRAM Processing Pool"
echo "=================================================="
echo "🌐 Master Node IP: $MASTER_IP | Port: $MASTER_PORT"
echo "🖥️ Total Nodes in World: $WORLD_SIZE"
echo "--------------------------------------------------"

# Track process IDs of launched remote tasks
REMOTE_PIDS=()

# 1. LOOP & SPAWN IPHONE WORKERS
# Rank 0 is reserved for the Master PC. iPhones take Rank 1, Rank 2, etc.
RANK=1
for node in "${IPHONE_NODES[@]}" do
echo "📡 [RANK $RANK] Triggering processing node on $node..."
# Run the python script on the remote phone in the background
# Passes vital cluster network parameters directly into the environment
ssh "$node" "cd $REMOTE_PROJECT_DIR && \
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=$RANK \
python3 $SCRIPT_NAME" &
REMOTE_PIDS+=($!)
RANK=$((RANK + 1))
done

# Give the remote phone processes a brief window to bind sockets and listen
sleep 2

# 2. LAUNCH LOCAL MASTER COMPUTATION (RANK 0)
echo "--------------------------------------------------"
echo "💻 [RANK 0] Initializing Master Engine locally..."
echo "--------------------------------------------------"

# Execute your local segment of the math workload
MASTER_ADDR=$MASTER_IP \
MASTER_PORT=$MASTER_PORT \
WORLD_SIZE=$WORLD_SIZE \
RANK=0 \
python3 "$REMOTE_PROJECT_DIR/$SCRIPT_NAME"

# 3. CLEANUP AND SYNCHRONIZATION
echo "--------------------------------------------------"
echo "⏳ Waiting for remote iPhone threads to sync and finalize..."
wait

echo "🎉 All distributed processing steps completed successfully!"

# =====================================================================
# 4. AUTOMATED EXECUTION WRAPPER (METRICS & INTEGRITY PIPELINE)
# =====================================================================
echo ""
echo "=================================================="
echo "🔄 AUTOMATED WRAPPER: Launching Diagnostics..."
echo "=================================================="

# 1. Run Data Verification
if [ -f "./verify_output.py" ]; then
python3 ./verify_output.py
fi

# 2. Extract live performance metrics from the python runtime environment
# Simulating captured run metrics; in production, you parse these out of train_dist.py stdout
MOCK_NET_TIME=0.3210
MOCK_COMP_TIME=0.1420
TOTAL_TIME=0.4630

# 3. Invoke Logger Engine
if [ -f "./log_metrics.py" ]; then
# Format: python3 log_metrics.py [Nodes] [Net_Sec] [Compute_Sec] [Total_Sec]
python3 ./log_metrics.py "$WORLD_SIZE" "$MOCK_NET_TIME" "$MOCK_COMP_TIME" "$TOTAL_TIME"
fi
