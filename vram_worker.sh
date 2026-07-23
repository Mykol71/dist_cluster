!/usr/bin/env bash

# CONFIGURATION
MAX_JOBS=4 # Maximum parallel jobs allowed
REQUIRED_VRAM=4000 # VRAM needed per job in MiB (e.g., 4GB)

# Queue of tasks (simulated Python deep learning or processing jobs)
tasks=(
"python3 train.py --dataset data1.csv"
"python3 train.py --dataset data2.csv"
"python3 train.py --dataset data3.csv"
"python3 train.py --dataset data4.csv"
"python3 train.py --dataset data5.csv"
"python3 train.py --dataset data6.csv"
)

# Function to get current free VRAM using nvidia-smi
get_free_vram() {
# Queries GPU 0 for free memory, strips the text, and returns raw integer
nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits -i 0
}

echo "Starting VRAM-aware parallel dispatcher..."

for task in "${tasks[@]}" do
while true; do
# 1. Check active background process count
current_jobs=$(jobs -r | wc -l)
# 2. Query live VRAM from hardware
free_vram=$(get_free_vram)

# 3. Decision Matrix
if (( current_jobs < MAX_JOBS )) && (( free_vram >= REQUIRED_VRAM )); then
echo "[LAUNCHING] VRAM: ${free_vram}MiB | Task: $task"
# Execute task in background, tracking its PID
$task &
# Brief pause to let the tool allocate its VRAM before the next check
sleep 3
break
else
echo "[WAITING] Slots Full ($current_jobs/$MAX_JOBS) or VRAM Low (${free_vram}MiB/$REQUIRED_VRAM MiB). Retrying..."
sleep 5
fi
done
done

# Wait for all background tasks to finish safely
wait
echo "All parallel GPU tasks completed successfully!"
