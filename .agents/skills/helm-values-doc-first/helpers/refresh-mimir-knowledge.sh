#!/usr/bin/env bash
set -euo pipefail

CHART_NAME="mimir-distributed"
CHART_REPO="grafana"
CHART_VERSION="${CHART_VERSION:-6.0.5}"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${BASE_DIR}/knowledge/${CHART_NAME}/${CHART_VERSION}"

mkdir -p "${OUT_DIR}"

PKG_API="https://artifacthub.io/api/v1/packages/helm/${CHART_REPO}/${CHART_NAME}/${CHART_VERSION}"
MIMIR_CFG_URL="https://grafana.com/docs/mimir/latest/configure/configuration-parameters/"

echo "[1/5] Fetch ArtifactHub package JSON"
curl -sSfL "${PKG_API}" > "${OUT_DIR}/artifacthub-package.json"

echo "[2/5] Extract ArtifactHub README"
jq -r '.readme // ""' "${OUT_DIR}/artifacthub-package.json" > "${OUT_DIR}/artifacthub-readme.md"

echo "[3/5] Download and cache values.yaml from chart artifact"
CONTENT_URL="$(jq -r '.content_url // empty' "${OUT_DIR}/artifacthub-package.json")"
if [[ -z "${CONTENT_URL}" ]]; then
  echo "content_url missing in ArtifactHub API response"
  exit 1
fi

TMP_TGZ="${OUT_DIR}/chart.tgz"
curl -sSfL "${CONTENT_URL}" -o "${TMP_TGZ}"
tar -xOf "${TMP_TGZ}" "${CHART_NAME}/values.yaml" > "${OUT_DIR}/values.yaml"

echo "[4/5] Cache Mimir configuration parameters page"
curl -sSfL "${MIMIR_CFG_URL}" > "${OUT_DIR}/mimir-config-parameters.html"

echo "[5/5] Build local summary"
TOP_LEVEL_KEYS="$(python3 - <<'PY' "${OUT_DIR}/values.yaml"
import sys, yaml
p=sys.argv[1]
with open(p,'r') as f:
    data=yaml.safe_load(f) or {}
for k in sorted(data.keys()):
    print(f"- {k}")
PY
)"

cat > "${OUT_DIR}/SUMMARY.md" <<EOF
# Knowledge Summary: ${CHART_NAME} ${CHART_VERSION}

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Primary sources

- ArtifactHub package page: https://artifacthub.io/packages/helm/${CHART_REPO}/${CHART_NAME}/${CHART_VERSION}
- ArtifactHub API JSON: ./artifacthub-package.json
- Chart values snapshot: ./values.yaml
- Mimir config parameters doc (HTML cache): ./mimir-config-parameters.html

## How to use this cache first

1. Für Helm Value-Fragen zuerst in values.yaml suchen.
2. Für Mimir Runtime-/Komponenten-Config in mimir-config-parameters.html nachschlagen.
3. Nur wenn dort nichts klar ist: tieferer Chart-Inspect.

## Top-level value keys (snapshot)

${TOP_LEVEL_KEYS}
EOF

rm -f "${TMP_TGZ}"

echo "Done. Knowledge cached in: ${OUT_DIR}"
