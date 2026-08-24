#!/usr/bin/env bash
# Força redeploy dos Rancher agents nos clusters downstream após troca de CA/certificado.
# Uso (no cluster local do Rancher):
#   ./scripts/06-force-redeploy-agents.sh c-xxxxx [c-yyyyy ...]
#   ./scripts/06-force-redeploy-agents.sh --all
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl é obrigatório." >&2
  exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  echo "Uso: $0 <CLUSTER_ID> [CLUSTER_ID...]"
  echo "     $0 --all"
  echo
  echo "O CLUSTER_ID aparece na URL do Rancher (Cluster Management), ex.: c-m-xxxxx"
  exit 0
fi

annotate_one() {
  local id="$1"
  echo "==> Forçando redeploy do agent: ${id}"
  kubectl annotate clusters.management.cattle.io "${id}" \
    io.cattle.agent.force.deploy=true --overwrite
}

if [[ "$1" == "--all" ]]; then
  mapfile -t IDS < <(kubectl get clusters.management.cattle.io -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -v '^local$' || true)
  if [[ ${#IDS[@]} -eq 0 ]]; then
    echo "Nenhum cluster downstream encontrado."
    exit 0
  fi
  for id in "${IDS[@]}"; do
    annotate_one "$id"
  done
else
  for id in "$@"; do
    annotate_one "$id"
  done
fi

echo
echo "OK. Aguarde os agents reconectarem."
echo "Em seguida: Continuous Delivery → Force Update nos clusters Fleet."
