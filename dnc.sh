#!/usr/bin/env bash

# IP Addresses provided by your Internet VPN (Tailscale)
MASTER_IP="100.11.22.33"
IPHONE_A_IP="100.11.22.44"
IPHONE_B_IP="100.11.22.55"

WORLD_SIZE=3 # Total number of participating devices
PORT=8080

echo "Initializing internet-distributed iPhone VRAM pool..."

# 1. Trigger the background process on iPhone A over the internet
ssh mobile@$IPHONE_A_IP "cd /app && mx.distributed --world-size $WORLD_SIZE --rank 1 --master-addr $MASTER_IP --master-port $PORT python3 train_dist.py" &

# 2. Trigger the background process on iPhone B over the internet
ssh mobile@$IPHONE_B_IP "cd /app && mx.distributed --world-size $WORLD_SIZE --rank 2 --master-addr $MASTER_IP --master-port $PORT python3 train_dist.py" &

# 3. Launch the master task locally on your primary machine
echo "Launching master process locally..."
mx.distributed --world-size $WORLD_SIZE --rank 0 --master-addr $MASTER_IP --master-port $PORT python3 train_dist.py

# Wait for internet execution to complete
wait
echo "Distributed processing across iPhone cluster finished successfully!"


# This launches commands over the internet instantly without passwords
ssh iphoneA "cd /app && python3 train_dist.py" &
ssh iphoneB "cd /app && python3 train_dist.py" &

wait
echo "All remote nodes completed tasks."
Would you like a script to verify the network connection speed between the master PC and the iPhones, or should we write a script to deploy the python files automatically to all phones at once?
