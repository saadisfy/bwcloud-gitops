#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  merge-common-values.sh <base-values.yaml> <stage1-values.yaml> [stage2-values.yaml ...] [--out <output.yaml>]

Behavior:
  - Computes the intersection of all stage values (keys/values present AND equal across all stages).
  - Merges that intersection into base (intersection overrides base).
  - Writes result to stdout or --out file.

List handling (arrays):
  - Default: arrays must be identical across all stages to be included.
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

OUT=""
BASE=""
STAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$BASE" ]]; then
        BASE="$1"
      else
        STAGES+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ -z "$BASE" || ${#STAGES[@]} -lt 1 ]]; then
  usage
  exit 1
fi

YQ_EXPR='
def intersect(a; b):
  if (a == null) or (b == null) then null
  elif (a|type) != (b|type) then null
  elif (a|type) == "!!map" then
    reduce (a|keys) as $k ({}; 
      if (b[$k] != null) then
        (intersect(a[$k]; b[$k])) as $iv
        | if $iv == null then . else . * {($k): $iv} end
      else . end
    )
  elif (a|type) == "!!seq" then
    if a == b then a else null end
  else
    if a == b then a else null end
  end;

def pruneNulls:
  if type == "!!map" then
    with_entries(.value |= pruneNulls)
    | with_entries(select(.value != null))
  elif type == "!!seq" then
    map(pruneNulls) | map(select(. != null))
  else
    .
  end;

def stageIntersection($docs):
  if ($docs|length) == 0 then {} 
  elif ($docs|length) == 1 then $docs[0]
  else reduce $docs[1:] as $d ($docs[0]; intersect(. ; $d))
  end;

(. as $docs
 | $docs[0] as $base
 | stageIntersection($docs[1:]) as $intersection
 | ($intersection | pruneNulls) as $clean
 | $base * $clean
)
'

if [[ -n "$OUT" ]]; then
  yq eval-all "$YQ_EXPR" "$BASE" "${STAGES[@]}" > "$OUT"
else
  yq eval-all "$YQ_EXPR" "$BASE" "${STAGES[@]}"
fi
