#!/usr/bin/env bash
# Aplica certificado TLS confiável no Rancher (cattle-system/tls-rancher-ingress).
# Uso:
#   ./scripts/04-aplicar-certificado-rancher.sh tls.crt tls.key [cacerts.pem]
#
# - tls.crt: certificado do servidor + intermediárias
# - tls.key: chave privada
# - cacerts.pem (opcional): CA privada (intermediária + root) → atualiza tls-ca e privateCA=true
#
# Se a instalação atual usa ingress.tls.source=rancher ou letsEncrypt, o script
# faz helm upgrade para source=secret (necessário para sair do autoassinado).
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

detect_tls_source() {
  if ! command -v helm >/dev/null 2>&1; then
    echo ""
    return
  fi
  # Prefer computed values (inclui defaults do chart)
  local src
  src=$(helm get values rancher -n cattle-system --all -o yaml 2>/dev/null \
    | awk '
        /^ingress:/ {in_ing=1; next}
        in_ing && /^[^ \t]/ {in_ing=0; in_tls=0}
        in_ing && /^[ \t]*tls:/ {in_tls=1; next}
        in_tls && /^[ \t]*source:/ { print $2; exit }
      ' || true)
  if [[ -z "$src" ]]; then
    src=$(helm get values rancher -n cattle-system -o yaml 2>/dev/null \
      | awk '/source:/{print $2; exit}' || true)
  fi
  echo "${src}"
}

rancher_chart_version() {
  local ver
  ver=$(helm ls -n cattle-system -o json 2>/dev/null \
    | sed -n 's/.*"chart":"rancher-\([^"]*\)".*/\1/p' | head -1)
  if [[ -z "$ver" ]]; then
    ver=$(helm ls -n cattle-system 2>/dev/null | awk '$1=="rancher"{print $8}' | sed 's/^rancher-//')
  fi
  echo "$ver"
}

write_tls_values() {
  # $1 = values file path, $2 = privateCA true|false
  local values="$1"
  local private_ca="$2"
  helm get values rancher -n cattle-system -o yaml >"$values" 2>/dev/null || echo "{}" >"$values"

  if grep -q '^privateCA:' "$values"; then
    sed -i "s/^privateCA:.*/privateCA: ${private_ca}/" "$values"
  else
    echo "privateCA: ${private_ca}" >>"$values"
  fi

  if grep -q 'source:' "$values"; then
    awk '
      /^ingress:/ {in_ing=1}
      in_ing && /tls:/ {in_tls=1}
      in_tls && /source:/ {sub(/source:.*/, "source: secret"); in_tls=0}
      {print}
    ' "$values" >"${values}.new" && mv "${values}.new" "$values"
  else
    cat >>"$values" <<'EOF'
ingress:
  tls:
    source: secret
EOF
  fi
}

helm_upgrade_rancher() {
  local values="$1"
  local chart_ver
  chart_ver=$(rancher_chart_version)
  echo "Usando chart version: ${chart_ver:-<sem --version>}"
  if [[ -n "$chart_ver" ]]; then
    helm upgrade rancher rancher-stable/rancher \
      --namespace cattle-system \
      -f "$values" \
      --version "$chart_ver"
  else
    echo "AVISO: versão do chart não detectada; upgrade sem --version." >&2
    helm upgrade rancher rancher-stable/rancher \
      --namespace cattle-system \
      -f "$values"
  fi
}

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

PRIVATE_CA=false
if [[ -n "$CA_FILE" ]]; then
  if [[ ! -f "$CA_FILE" ]]; then
    echo "CA file não encontrado: $CA_FILE" >&2
    exit 1
  fi
  echo "==> Aplicando secret tls-ca (CA privada)..."
  TMPDIR=$(mktemp -d)
  cp "$CA_FILE" "${TMPDIR}/cacerts.pem"
  kubectl -n cattle-system create secret generic tls-ca \
    --from-file=cacerts.pem="${TMPDIR}/cacerts.pem" \
    --dry-run=client --save-config -o yaml | kubectl apply -f -
  rm -rf "${TMPDIR}"
  PRIVATE_CA=true
fi

CURRENT_SOURCE=$(detect_tls_source)
echo "Fonte TLS atual detectada: ${CURRENT_SOURCE:-desconhecida}"

# Precisa helm upgrade se: CA privada, ou saindo de rancher/letsEncrypt, ou source desconhecida
NEED_HELM=0
if [[ "$PRIVATE_CA" == "true" ]]; then
  NEED_HELM=1
elif [[ "$CURRENT_SOURCE" == "rancher" || "$CURRENT_SOURCE" == "letsEncrypt" ]]; then
  NEED_HELM=1
elif [[ -z "$CURRENT_SOURCE" ]]; then
  echo "AVISO: não foi possível detectar ingress.tls.source; forçando helm upgrade para secret." >&2
  NEED_HELM=1
fi

if [[ "$NEED_HELM" -eq 1 ]]; then
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm é obrigatório para migrar ingress.tls.source → secret." >&2
    echo "Aplique manualmente: ingress.tls.source=secret e privateCA=${PRIVATE_CA}" >&2
    exit 1
  fi
  echo "==> Helm upgrade: ingress.tls.source=secret, privateCA=${PRIVATE_CA}"
  VALUES=$(mktemp)
  write_tls_values "$VALUES" "$PRIVATE_CA"
  helm_upgrade_rancher "$VALUES"
  rm -f "$VALUES"
else
  echo "==> Fonte já é secret; reiniciando pods Rancher para recarregar o certificado..."
  kubectl rollout restart deploy/rancher -n cattle-system
  kubectl rollout status deploy/rancher -n cattle-system --timeout=300s
fi

echo
echo "Próximos passos:"
echo "1. Validar: openssl s_client -connect <FQDN>:443 -servername <FQDN>"
echo "2. Se a CA mudou (saiu do autoassinado), force redeploy dos agents:"
echo "   ./scripts/06-force-redeploy-agents.sh <CLUSTER_ID> [mais IDs...]"
echo "3. Continuous Delivery → Force Update nos clusters Fleet"
echo "4. Repita o scan Nessus nos plugins de certificado"
