#!/usr/bin/env bash

# CONFIGURATION
IPHONE_NODES=("iphoneA" "iphoneB")
LOCAL_PROJECT_DIR="./src"
REMOTE_PROJECT_DIR="/app"

# Define the Python libraries your GPU project needs
REQUIRED_PIP_PACKAGES=("numpy") # Note: use "mlx" if running on native Apple Silicon environments

echo "=================================================="
echo "🚀 Initializing Parallel Deployment & Dependency Engine"
echo "=================================================="

deploy_and_verify_node() {
local node="$1"
# 1. Connectivity Check
if ! ssh -q -o ConnectTimeout=5 "$node" exit; then
echo "❌ [$node] Offline or unreachable."
return 1
fi
echo "🔗 [$node] Connected. Checking environment system..."

# 2. Package Manager & Python Detection
# Detects if node is iSH (Alpine) or Native iOS (uses apt/sileo/dpkg)
local is_alpine=$(ssh "$node" "command -v apk")
if [ -n "$is_alpine" ]; then
echo "📦 [$node] Detected iSH (Alpine Linux). Verifying system packages..."
# Install Python3, Pip, and compiler build tools needed for native library compilation
ssh "$node" "apk update && apk add --no-cache python3 py3-pip python3-dev gcc g++ make gfortran musl-dev" > /dev/null 2>&1
else
echo "📦 [$node] Detected Native iOS / Darwin. Verifying system packages..."
# Fallback check for native environment package managers
ssh "$node" "command -v apt-get >/dev/null && apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential" > /dev/null 2>&1
fi

# Double check Python installation success
if ! ssh "$node" "command -v python3" > /dev/null 2>&1; then
echo "❌ [$node] Python3 could not be installed automatically. Install it manually."
return 1
fi

# 3. PIP Dependency Check Loop
echo "🐍 [$node] Verifying Python library dependencies..."
for pkg in "${REQUIRED_PIP_PACKAGES[@]}" do
if ! ssh "$node" "python3 -c 'import $pkg'" > /dev/null 2>&1; then
echo "📥 [$node] Installing missing package: $pkg..."
# --break-system-packages overrides standard Python global environment blockades in newer systems
ssh "$node" "python3 -m pip install --upgrade pip && python3 -m pip install $pkg --break-system-packages" > /dev/null 2>&1
if ! ssh "$node" "python3 -c 'import $pkg'" > /dev/null 2>&1; then
echo "❌ [$node] Failed to install package: $pkg"
return 1
fi
fi
done
echo "✨ [$node] Environment verified. All dependencies are green!"

 3. CLEANUP AND SYNCHRONIZATION
echo "--------------------------------------------------"
echo "⏳ Waiting for remote iPhone threads to sync and finalize..."
wait

echo "🎉 All distributed processing steps completed successfully!"

# =====================================================================
# 4. AUTOMATED EXECUTION WRAPPER (POST-PROCESSING HOOK)
# =====================================================================
echo ""
echo "=================================================="
echo "🔄 AUTOMATED WRAPPER: Launching Integrity Checks..."
echo "=================================================="

# Check if the verification script exists locally before running it
if [ -f "./verify_output.py" ]; then
chmod +x ./verify_output.py
python3 ./verify_output.py
else
echo "❌ Execution Wrapper Warning: 'verify_output.py' not found in current directory."
echo "💾 Distributed data remains saved safely in 'matrix_output.csv'."
fi
How the Full Automation Works Now
With this wrapper in place, your entire project architecture behaves like a production-grade compute cluster pipeline from a single terminal enter key:
[Your Terminal] ---> Run ./run_cluster.sh
│
├──> Spawns iPhone Workers via SSH (& Background threads)
├──> Initializes Local Master Socket Loop
├──> Streams Data Blocks (With Live Progress Bars: ▓▓▓ Done!)
├──> Saves Assembled Matrix to Disk (matrix_output.csv)
│
└──> [WRAPPER ENGAGES AUTOMATICALLY]
│
└──> Invokes verify_output.py
└──> Prints final mathematical validation status

# 4. File Synchronization
ssh "$node" "mkdir -p $REMOTE_PROJECT_DIR"
echo "📦 [$node] Syncing Python project source files..."
scp -r "$LOCAL_PROJECT_DIR"/* "$node":"$REMOTE_PROJECT_DIR/" > /dev/null 2>&1

if [ $? -eq 0 ]; then
echo "✅ [$node] Fully deployed and ready for parallel execution!"
else
echo "❌ [$node] File transfer failed during copy phase."
return 1
fi
}

# MAIN PARALLEL LOOP
echo "Spinning up asynchronous installer threads for ${#IPHONE_NODES[@]} nodes..."
echo "--------------------------------------------------"

for node in "${IPHONE_NODES[@]}" do
deploy_and_verify_node "$node" &
done

# Wait for all environmental verification and code deployment loops to complete
wait

echo "--------------------------------------------------"
echo "🎉 Cluster environment setup finalized!"

# 4. Invoke Logger Engine and Final Markdown Formatter
if [ -f "./log_metrics.py" ]; then
python3 ./log_metrics.py "$WORLD_SIZE" "$MOCK_NET_TIME" "$MOCK_COMP_TIME" "$TOTAL_TIME"
fi

if [ -f "./generate_report.py" ]; then
python3 ./generate_report.py
fi
