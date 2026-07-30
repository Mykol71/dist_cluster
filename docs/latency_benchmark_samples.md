# Latency Profiling and Link Admission

`src/ping_test.py` profiles each worker immediately before launch. It parses
average round-trip latency, mdev/stddev, and packet loss from the operating
system's `ping` summary. Accepted links receive a chunk-size recommendation;
rejected links stop `run_cluster.sh` before any workers start.

The probe count defaults to 10 and can be changed with `PING_COUNT`.

## Decision table

| avg latency | mdev | packet loss | Recommended action |
|---|---:|---:|---|
| `< 30 ms` | `< 10 ms` | `0%` | Proceed, 256 KB chunks |
| `30–80 ms` | `10–40 ms` | `0%` | Proceed, 1 MB chunks |
| `80–150 ms` | `> 40 ms` | `< 1%` | Proceed cautiously, 2 MB chunks |
| `> 150 ms` | any | any | Abort; re-profile after fix |
| any | any | `> 2%` | Abort; unstable link |

Classification is conservative and uses the worst observed condition. For
example, low average latency with mdev above 40 ms uses the cautious 2 MB tier.
Packet loss from 1–2% does not satisfy any proceed tier and therefore aborts.

## Examples

Healthy Wi-Fi:

```text
rtt min/avg/max/mdev = 12.00/20.00/35.00/8.00 ms
10 packets transmitted, 10 received, 0% packet loss
```

Result: proceed with 256 KB chunks.

Moderate link:

```text
rtt min/avg/max/mdev = 20.00/55.00/120.00/30.00 ms
10 packets transmitted, 10 received, 0% packet loss
```

Result: proceed with 1 MB chunks.

High-jitter link:

```text
rtt min/avg/max/mdev = 70.00/120.00/190.00/55.00 ms
100 packets transmitted, 100 received, 0% packet loss
```

Result: proceed cautiously with 2 MB chunks.

Unstable link:

```text
rtt min/avg/max/mdev = 80.00/180.00/450.00/95.00 ms
100 packets transmitted, 96 received, 4% packet loss
```

Result: abort before worker launch.

## Manual use

```bash
python3 src/ping_test.py worker1
```

Accepted profiles are printed as JSON:

```json
{"avg_latency_ms":20.0,"mdev_ms":8.0,"packet_loss_percent":0.0,"status":"proceed","action":"Proceed, 256 KB chunks","buffer_size":262144,"host":"worker1"}
```

An abort profile exits with status 2, allowing shell automation to fail closed.
