import mlx.core as mx
import mlx.nn as nn

# Initializes communication across the internet link
mx.distributed.init()

rank = mx.distributed.get_rank()
world_size = mx.distributed.get_world_size()

# Example: Create a large weight matrix.
# Because of distributed routing, the massive memory footprint is safely split across the devices.
if rank == 0:
print(f"Master node online. Clustering VRAM across {world_size} devices.")

# Perform an all-reduce operation across the internet to sync computations
x = mx.array([1.0, 2.0, 3.0]) * (rank + 1)
sum_x = mx.distributed.all_sum(x)

print(f"Device Rank {rank} finished computation step. Synchronized data: {sum_x}")

