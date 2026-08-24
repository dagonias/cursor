#!/usr/bin/env bash
# Aplica certificado TLS confiável no Rancher (cattle-system/tls-rancher-ingress).
# Uso:
#   ./scripts/04-aplicar-certificado-rancher.sh tls.crt tls.key [cacerts.pem]
#
# - tls.crt: certificado do servidor + intermediárias
# - tls.key: chave privada
# - cacerts.pem (opcional): CA privada (intermediária + root) → atualiza tls-ca e privateCA
set -euo pipefail

CERT="${1:-}"
KEY="${2:-}"
CA_FILE="${3:-}"

if [[ -z "$CERT" || -z "$KEY" ]]; then
  echo "Uso: $0 <tls.crt> <tls.key> [cacerts.pem]" >&2
  exit 1
fi
if [[ ! -f "$CERT" || ! -f "$KEY" ]]; then
  echo "Arquivos de certificado/chave não encontrados." >&2
  exit 1
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl é obrigatório." >&2
  exit 1
fi

echo "==> Validando certificado..."
openssl x509 -in "$CERT" -noout -subject -issuer -dates -ext subjectAltName
openssl rsa -in "$KEY" -check -noout 2>/dev/null || openssl ec -in "$KEY" -check -noout

CN_OR_SAN=$(openssl x509 -in "$CERT" -noout -ext subjectAltName 2>/dev/null || true)
SUBJ=$(openssl x509 -in "$CERT" -noout -subject)
echo "Subject: ${SUBJ}"
echo "SAN: ${CN_OR_SAN:-"(verifique CN se SAN vazio)"}"
echo "IMPORTANTE: o FQDN usado no scan/acesso deve aparecer no SAN."

echo "==> Aplicando secret tls-rancher-ingress..."
kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert="$CERT" \
  --key="$KEY" \
  --dry-run=client --save-config -o yaml | kubectl apply -f -

NEED_HELM_PRIVATE_CA=0
if [[ -n "$CA_FILE" ]]; then
  if [[ ! -f "$CA_FILE" ]]; then
    echo "CA file não encontrado: $CA_FILE" >&2
    exit 1
  fi
  echo "==> Aplicando secret tls-ca (CA privada)..."
  # Secret espera a chave 'cacerts.pem'
  TMPDIR=$(mktemp -d)
  cp "$CA_FILE" "${TMPDIR}/cacerts.pem"
  kubectl -n cattle-system create secret generic tls-ca \
    --from-file=cacerts.pem="${TMPDIR}/cacerts.pem" \
    --dry-run=client --save-config -o yaml | kubectl apply -f -
  rm -rf "${TMPDIR}"
  NEED_HELM_PRIVATE_CA=1
fi

CURRENT_SOURCE=""
if command -v helm >/dev/null 2>&1; then
  CURRENT_SOURCE=$(helm get values rancher -n cattle-system -o yaml 2>/dev/null \
    | awk '/^ingress:/{p=1} p&&/source:/{print $2; exit}' || true)
fi

if [[ "$NEED_HELM_PRIVATE_CA" -eq 1 ]]; then
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm não encontrado; aplique manualmente ingress.tls.source=secret e privateCA=true" >&2
    exit 1
  fi
  echo "==> Atualizando Helm values (secret + privateCA)..."
  VALUES=$(mktemp)
  helm get values rancher -n cattle-system -o yaml >"$VALUES"
  # Garante blocos mínimos via append se não existirem — operador deve revisar
  if ! grep -q 'privateCA:' "$VALUES"; then
    echo "privateCA: true" >>"$VALUES"
  else
    sed -i 's/privateCA:.*/privateCA: true/' "$VALUES"
  fi
  if ! grep -q 'source:' "$VALUES"; then
    cat >>"$VALUES" <<'EOF'
ingress:
  tls:
    source: secret
EOF
  else
    # best-effort: força source secret na árvore tls
    awk '
      /^ingress:/ {in_ing=1}
      in_ing && /tls:/ {in_tls=1}
      in_tls && /source:/ {sub(/source:.*/, "source: secret"); in_tls=0}
      {print}
    ' "$VALUES" >"${VALUES}.new" && mv "${VALUES}.new" "$VALUES"
  fi
  # Extrai versão do chart (ex.: rancher-2.12.3 → 2.12.3)
  CHART_VER=$(helm ls -n cattle-system -o json 2>/dev/null | sed -n 's/.*"chart":"rancher-\([^"]*\)".*/\1/p' | head -1)
  if [[ -z "${CHART_VER}" ]]; then
    CHART_VER=$(helm ls -n cattle-system 2>/dev/null | awk '$1=="rancher"{print $8}' | sed 's/^rancher-//')
  fi
  echo "Usando chart version: ${CHART_VER:-<mesma do release / sem --version>}"
  if [[ -n "${CHART_VER}" ]]; then
    helm upgrade rancher rancher-stable/rancher \
      --namespace cattle-system \
      -f "$VALUES" \
      --version "$CHART_VER"
  else
    echo "AVISO: versão do chart não detectada; upgrade sem --version (revise se necessário)." >&2
    helm upgrade rancher rancher-stable/rancher \
      --namespace cattle-system \
      -f "$VALUES"
  fi
  rm -f "$VALUES"
else
  echo "==> Reiniciando pods Rancher para recarregar o certificado..."
  kubectl rollout restart deploy/rancher -n cattle-system
  kubectl rollout status deploy/rancher -n cattle-system --timeout=300s
fi

echo
echo "Próximos passos:"
echo "1. Validar: openssl s_client -connect <FQDN>:443 -servername <FQDN>"
echo "2. Se a CA mudou, force redeploy dos agents:"
echo "   kubectl annotate clusters.management.cattle.io <CLUSTER_ID> io.cattle.agent.force.deploy=true"
echo "3. Continuous Delivery → Force Update nos clusters Fleet"
echo "4. Repita o scan Nessus nos plugins de certificado"
