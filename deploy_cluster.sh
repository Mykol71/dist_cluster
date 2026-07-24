#!/usr/bin/env bash

# CONFIGURATION
WORKER_NODES=("iphoneA" "iphoneB")
LOCAL_PROJECT_DIR="./src"
DEFAULT_LINUX_REMOTE_PROJECT_DIR="/app"
DEFAULT_DARWIN_REMOTE_PROJECT_DIR="dist_cluster"

# Define the Python libraries your GPU project needs
REQUIRED_PIP_PACKAGES=("numpy") # Note: use "mlx" if running on native Apple Silicon environments

echo "=================================================="
echo "🚀 Initializing Parallel Deployment & Dependency Engine"
echo "=================================================="

get_remote_os() {
local node="$1"
ssh -q -o ConnectTimeout=5 -o BatchMode=yes "$node" "uname -s" 2>/dev/null || true
}

get_remote_project_dir() {
local node="$1"
if [ -n "${REMOTE_PROJECT_DIR:-}" ]; then
printf '%s\n' "$REMOTE_PROJECT_DIR"
return 0
fi

case "$(get_remote_os "$node")" in
Darwin)
ssh -q -o ConnectTimeout=5 -o BatchMode=yes "$node" "printf '%s\n' \"\$HOME/$DEFAULT_DARWIN_REMOTE_PROJECT_DIR\"" 2>/dev/null
;;
*)
printf '%s\n' "$DEFAULT_LINUX_REMOTE_PROJECT_DIR"
;;
esac
}

deploy_and_verify_node() {
local node="$1"
# 1. Connectivity Check
if ! ssh -q -o ConnectTimeout=5 "$node" exit; then
echo "❌ [$node] Offline or unreachable."
return 1
fi
echo "🔗 [$node] Connected. Checking environment system..."

# 2. OS, project path, and Python detection
local remote_os
remote_os=$(get_remote_os "$node")
if [ -z "$remote_os" ]; then
echo "❌ [$node] Could not detect the remote operating system."
return 1
fi

local remote_project_dir
remote_project_dir=$(get_remote_project_dir "$node")
if [ -z "$remote_project_dir" ]; then
echo "❌ [$node] Could not determine a writable remote project directory."
return 1
fi

case "$remote_os" in
Linux)
if ssh "$node" "command -v apk >/dev/null 2>&1"; then
echo "📦 [$node] Detected Alpine Linux. Verifying system packages..."
ssh "$node" "apk update && apk add --no-cache python3 py3-pip python3-dev gcc g++ make gfortran musl-dev" > /dev/null 2>&1
elif ssh "$node" "command -v apt-get >/dev/null 2>&1"; then
echo "📦 [$node] Detected Debian/Ubuntu Linux. Verifying system packages..."
ssh "$node" "apt-get update && apt-get install -y python3 python3-pip python3-dev build-essential" > /dev/null 2>&1
else
echo "⚠️  [$node] Unsupported Linux package manager. Assuming Python is preinstalled."
fi
;;
Darwin)
echo "📦 [$node] Detected macOS. Verifying Python environment..."
if ! ssh "$node" "command -v python3 >/dev/null 2>&1"; then
if ssh "$node" "command -v brew >/dev/null 2>&1"; then
ssh "$node" "brew install python" > /dev/null 2>&1
else
echo "❌ [$node] Python3 is missing and Homebrew is unavailable. Install Python3 manually."
return 1
fi
fi
ssh "$node" "python3 -m ensurepip --upgrade >/dev/null 2>&1 || true" > /dev/null 2>&1
;;
*)
echo "❌ [$node] Unsupported operating system: $remote_os"
return 1
;;
esac

# Double check Python installation success
if ! ssh "$node" "command -v python3" > /dev/null 2>&1; then
echo "❌ [$node] Python3 could not be installed automatically. Install it manually."
return 1
fi

if ! ssh "$node" "python3 -m pip --version" > /dev/null 2>&1; then
echo "❌ [$node] pip is unavailable for python3. Install it manually."
return 1
fi

# 3. PIP Dependency Check Loop
echo "🐍 [$node] Verifying Python library dependencies..."
for pkg in "${REQUIRED_PIP_PACKAGES[@]}"; do
if ! ssh "$node" "python3 -c 'import $pkg'" > /dev/null 2>&1; then
echo "📥 [$node] Installing missing package: $pkg..."
if [ "$remote_os" = "Darwin" ]; then
ssh "$node" "python3 -m pip install --upgrade pip && python3 -m pip install --user $pkg" > /dev/null 2>&1
else
# --break-system-packages overrides standard Python global environment blockades in newer Linux systems
ssh "$node" "python3 -m pip install --upgrade pip && python3 -m pip install $pkg --break-system-packages" > /dev/null 2>&1
fi
if ! ssh "$node" "python3 -c 'import $pkg'" > /dev/null 2>&1; then
echo "❌ [$node] Failed to install package: $pkg"
return 1
fi
fi
done
echo "✨ [$node] Environment verified. All dependencies are green!"

# 4. File Synchronization
ssh "$node" "mkdir -p \"$remote_project_dir\""
echo "📦 [$node] Syncing Python project source files..."
scp -r "$LOCAL_PROJECT_DIR"/* "$node":"$remote_project_dir/" > /dev/null 2>&1

if [ $? -eq 0 ]; then
echo "✅ [$node] Fully deployed and ready for parallel execution!"
else
echo "❌ [$node] File transfer failed during copy phase."
return 1
fi
}

# MAIN PARALLEL LOOP
echo "Spinning up asynchronous installer threads for ${#WORKER_NODES[@]} nodes..."
echo "--------------------------------------------------"

for node in "${WORKER_NODES[@]}"; do
deploy_and_verify_node "$node" &
done

# Wait for all environmental verification and code deployment loops to complete
wait

echo "--------------------------------------------------"
echo "🎉 Cluster environment setup finalized!"
