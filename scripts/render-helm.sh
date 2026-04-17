#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <chart-dir> [release-name] [namespace]"
  exit 1
fi

chart_dir="${1%/}"
release_name="${2:-$(basename "$chart_dir")}" 
namespace="${3:-$(basename "$chart_dir")}" 

if [[ ! -f "$chart_dir/Chart.yaml" ]]; then
  echo "Error: Chart.yaml not found in $chart_dir"
  exit 1
fi

out_file="$chart_dir/render.yaml"

args=(template "$release_name" "$chart_dir" --namespace "$namespace")

if [[ -f "$chart_dir/../base/values.yaml" ]]; then
  args+=(--values "$chart_dir/../base/values.yaml")
fi

if [[ -f "$chart_dir/values.yaml" ]]; then
  args+=(--values "$chart_dir/values.yaml")
fi

helm "${args[@]}" > "$out_file"

echo "Rendered to: $out_file"
