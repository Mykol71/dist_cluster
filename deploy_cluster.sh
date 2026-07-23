#!/usr/bin/env bash

# CONFIGURATION
# List the exact host aliases you defined in your ~/.ssh/config file
IPHONE_NODES=("iphoneA" "iphoneB")

# The local folder on your PC containing your Python files
LOCAL_PROJECT_DIR="./src"

# The target directory path on the iPhones where code will live
REMOTE_PROJECT_DIR="/app"

echo "=================================================="
echo "🚀 Initializing Parallel Python Deployment to Cluster"
echo "=================================================="

# Function to handle deployment for a single node
deploy_to_node() {
local node="$1"
# 1. Ping test the SSH connection to ensure the phone is awake/online
if ! ssh -q -o ConnectTimeout=5 "$node" exit; then
echo "❌ [$node] Offline or unreachable. Skipping."
return 1
fi
echo "🔗 [$node] Connection verified. Preparing remote directories..."

# 2. Ensure the remote project directory exists on the iPhone
ssh "$node" "mkdir -p $REMOTE_PROJECT_DIR"
if [ $? -ne 0 ]; then
echo "❌ [$node] Failed to create directory: $REMOTE_PROJECT_DIR"
return 1
fi

# 3. Securely copy files over the internet tunnel using rsync or scp
echo "📦 [$node] Syncing Python files..."
# Using scp (built-in fallback). It copies all python files from the local directory
scp -r "$LOCAL_PROJECT_DIR"/* "$node":"$REMOTE_PROJECT_DIR/" > /dev/null 2>&1

if [ $? -eq 0 ]; then
echo "✅ [$node] Deployment successful!"
else
echo "❌ [$node] File transfer failed during copy phase."
return 1
fi
}

# MAIN EXECUTION LOOP
echo "Starting parallel push to ${#IPHONE_NODES[@]} devices..."
echo "--------------------------------------------------"

# Loop through all nodes and launch the deployment function in the background
for node in "${IPHONE_NODES[@]}" do
deploy_to_node "$node" &
done

# Wait for all background parallel deployment tasks to finish
wait

echo "--------------------------------------------------"
echo "🎉 Deployment cycle complete. Checking cluster status..."

# Optional: Run a quick remote diagnostic command in parallel across all phones
for node in "${IPHONE_NODES[@]}" do
(
files_count=$(ssh "$node" "ls -1 $REMOTE_PROJECT_DIR/*.py 2>/dev/null | wc -l")
echo "📊 [$node] Currently hosting $files_count python script(s) in $REMOTE_PROJECT_DIR"
) &
done

wait
echo "Ready to run your parallel VRAM workloads!"

