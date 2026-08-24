#!/usr/bin/env bash
# Verifica imagens do ingress-nginx (RKE2/Rancher) e orienta upgrade.
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl é obrigatório." >&2
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Cluster inacessível. Exporte KUBECONFIG (ex.: /etc/rancher/rke2/rke2.yaml)." >&2
  exit 1
fi

echo "=== Pods / imagens relacionados a ingress-nginx ==="
kubectl get pods -A -o wide 2>/dev/null | grep -iE 'ingress-nginx|nginx-ingress' || echo "(nenhum)"

echo
echo "=== Imagens detalhadas ==="
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
  | grep -iE 'ingress-nginx|nginx-ingress|nginx-ingress-controller' || echo "(nenhuma imagem encontrada)"

echo
echo "=== HelmChart / HelmChartConfig RKE2 ==="
kubectl get helmchart,helmchartconfig -A 2>/dev/null | grep -i ingress || echo "(não encontrado — pode ser K3s/Traefik ou instalação custom)"

echo
echo "=== Versão RKE2 (se instalado neste nó) ==="
if command -v rke2 >/dev/null 2>&1; then
  rke2 --version || true
elif [[ -x /usr/local/bin/rke2 ]]; then
  /usr/local/bin/rke2 --version || true
else
  echo "binário rke2 não no PATH deste host"
fi

echo
echo "=== Como remediar os findings de nginx no Rancher ==="
cat <<'EOF'
1. Confirme se o Nessus bate no VIP/hostname do ingress do cluster (não em nginx do SO).
2. No Rancher UI: Cluster Management → ⋮ → Edit Config → Kubernetes Version
   → escolha um release RKE2 recente suportado pelo Rancher 2.12.
3. Aguarde o upgrade rolling dos nós e pods do ingress.
4. Revalide as imagens com este script.
5. Se houver nginx no host Rocky 9, rode também: sudo ./scripts/03-atualizar-nginx-host.sh

Alvo de versão nginx (CVE-2026-1642): 1.28.2+ ou 1.29.5+.
O controller RKE2 embute o nginx; a correção vem via upgrade do RKE2/imagem
rancher/nginx-ingress-controller, não via dnf no nó (exceto se o pacote host
também estiver exposto).

Referências:
- F5 K000159824 / CVE-2026-1642
- Docs Rancher 2.12: update certificate + upgrade Kubernetes version
EOF
