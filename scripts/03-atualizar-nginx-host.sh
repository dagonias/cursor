#!/usr/bin/env bash
# Atualiza nginx instalado no Rocky Linux 9 (host).
# Se o finding vier do ingress-nginx do RKE2, use o script 05.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute como root (sudo)." >&2
  exit 1
fi

if ! rpm -q nginx >/dev/null 2>&1; then
  echo "Pacote nginx não está instalado neste host."
  echo "Se o Nessus ainda reportar nginx, o alvo provavelmente é o ingress do cluster."
  echo "Execute: ./scripts/05-verificar-ingress-nginx.sh"
  exit 0
fi

echo "==> Versão atual:"
rpm -q nginx
nginx -v 2>&1 || true

echo "==> Atualizando via dnf..."
dnf update -y nginx || dnf update -y nginx*

echo "==> Versão após update:"
rpm -q nginx
nginx -v 2>&1 || true

VER=$(nginx -v 2>&1 | sed -n 's/.*nginx\///p' | tr -d '[:space:]')
echo "Versão reportada: ${VER}"

# Alvo CVE-2026-1642: >= 1.28.2 (stable) ou >= 1.29.5 (mainline)
is_older() {
  # retorna 0 se $1 < $2
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" && "$1" != "$2" ]]
}

MINOR=$(echo "$VER" | cut -d. -f2)
if [[ "$MINOR" == "29" ]]; then
  if is_older "$VER" "1.29.5"; then
    echo "ATENÇÃO: ${VER} < 1.29.5. Considere pacote do nginx.org ou rebuild."
  else
    echo "OK para linha 1.29.x (>= 1.29.5)."
  fi
else
  if is_older "$VER" "1.28.2"; then
    echo "ATENÇÃO: ${VER} < 1.28.2. AppStream pode não ter o patch ainda."
    echo "Opções: build nginx.org 1.28.2+/1.29.5+, ou desabilitar o serviço se não for usado."
  else
    echo "OK: versão parece >= 1.28.2"
  fi
fi

if systemctl is-enabled nginx >/dev/null 2>&1; then
  systemctl restart nginx
  systemctl --no-pager status nginx | head -15
fi

echo "Concluído."
