#!/usr/bin/env bash
# Launch MLX-LM pipeline-parallel inference on Apple Silicon Macs.

set -euo pipefail

MODEL="mlx-community/Llama-3.2-3B-Instruct-4bit"
BACKEND="ring"
HOSTFILE=""
LOCAL_RANKS=2
MAX_TOKENS=128
PROMPT=""
OUTPUT_FILE="${OUTPUT_DIR:-output}/llm_response.txt"
TRUST_REMOTE_CODE=0
DRY_RUN=0
SKIP_LATENCY_CHECK=0

usage() {
  cat <<'EOF'
Usage: bash run_llm_cluster.sh [options]

Options:
  --model MODEL          MLX model directory or Hugging Face repository
  --hostfile FILE        MLX ring/JACCL hostfile for remote Macs
  --backend BACKEND      ring or jaccl (default: ring)
  --local-ranks N        Local processes when no hostfile is supplied (default: 2)
  --prompt TEXT          Run one prompt noninteractively and save the response
  --max-tokens N         Maximum generated tokens (default: 128)
  --output FILE          Noninteractive response path
  --trust-remote-code    Allow model-specific remote tokenizer/model code
  --skip-latency-check   Skip project link admission for hostfile nodes
  --dry-run              Print the launch command without executing it
  -h, --help             Show this help
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) MODEL=${2:?missing model}; shift 2 ;;
    --hostfile) HOSTFILE=${2:?missing hostfile}; shift 2 ;;
    --backend) BACKEND=${2:?missing backend}; shift 2 ;;
    --local-ranks) LOCAL_RANKS=${2:?missing rank count}; shift 2 ;;
    --prompt) PROMPT=${2:?missing prompt}; shift 2 ;;
    --max-tokens) MAX_TOKENS=${2:?missing token count}; shift 2 ;;
    --output) OUTPUT_FILE=${2:?missing output path}; shift 2 ;;
    --trust-remote-code) TRUST_REMOTE_CODE=1; shift ;;
    --skip-latency-check) SKIP_LATENCY_CHECK=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$BACKEND" in ring|jaccl) ;; *) echo "BACKEND must be ring or jaccl." >&2; exit 2 ;; esac
[[ "$LOCAL_RANKS" =~ ^[1-9][0-9]*$ ]] || { echo "LOCAL_RANKS must be positive." >&2; exit 2; }
[[ "$MAX_TOKENS" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_TOKENS must be positive." >&2; exit 2; }
if [ -n "$HOSTFILE" ] && [ ! -f "$HOSTFILE" ]; then
  echo "Hostfile not found: $HOSTFILE" >&2
  exit 2
fi

LAUNCH=(mlx.launch --backend "$BACKEND")
if [ -n "$HOSTFILE" ]; then
  LAUNCH+=(--hostfile "$HOSTFILE")
else
  LAUNCH+=(-n "$LOCAL_RANKS")
fi
LAUNCH+=(--env MLX_METAL_FAST_SYNCH=1 -- mlx_lm.chat --pipeline)
LAUNCH+=(--model "$MODEL" --max-tokens "$MAX_TOKENS")
if [ "$TRUST_REMOTE_CODE" -eq 1 ]; then
  LAUNCH+=(--trust-remote-code)
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'Launch command:'
  printf ' %q' "${LAUNCH[@]}"
  printf '\n'
  if [ -n "$PROMPT" ]; then
    printf 'Prompt: %s\nOutput: %s\n' "$PROMPT" "$OUTPUT_FILE"
  fi
  exit 0
fi

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "MLX-LM requires an Apple Silicon Mac (Darwin arm64)." >&2
  exit 1
fi
command -v mlx.launch >/dev/null 2>&1 || {
  echo "mlx.launch not found. Install MLX-LM: python3 -m pip install mlx-lm" >&2
  exit 1
}
command -v mlx_lm.chat >/dev/null 2>&1 || {
  echo "mlx_lm.chat not found. Install MLX-LM on every participating Mac." >&2
  exit 1
}

if [ -n "$HOSTFILE" ] && [ "$SKIP_LATENCY_CHECK" -eq 0 ]; then
  while IFS= read -r host; do
    [ -z "$host" ] && continue
    if ! profile=$(python3 src/ping_test.py "$host"); then
      echo "Latency admission rejected $host; LLM launch aborted." >&2
      exit 1
    fi
    python3 -c '
import json, sys
p=json.loads(sys.argv[1])
print("[{}] avg={}ms mdev={}ms loss={}% — {}".format(
    p["host"], p["avg_latency_ms"], p["mdev_ms"],
    p["packet_loss_percent"], p["action"]
))
' "$profile"
  done < <(python3 - "$HOSTFILE" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
if isinstance(data, dict):
    data = data.get("hosts", [])
for entry in data:
    host = entry.get("ssh") if isinstance(entry, dict) else None
    if host and host not in {"localhost", "127.0.0.1"}:
        print(host)
PY
)
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
if [ -n "$PROMPT" ]; then
  {
    printf '%s\n' "$PROMPT"
    printf 'q\n'
  } | "${LAUNCH[@]}" | tee "$OUTPUT_FILE"
  echo "LLM response saved to $OUTPUT_FILE"
else
  exec "${LAUNCH[@]}"
fi
