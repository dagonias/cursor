#!/usr/bin/env bash
# Mitiga CVE-2023-48795 (Terrapin) em Rocky Linux 9.
# - Atualiza OpenSSH
# - Aplica subpolicy crypto desabilitando ChaCha20-Poly1305 e MACs ETM
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute como root (sudo)." >&2
  exit 1
fi

echo "==> Atualizando OpenSSH..."
dnf update -y openssh openssh-server openssh-clients

POLICY_DIR=/etc/crypto-policies/policies/modules
mkdir -p "${POLICY_DIR}"

cat >"${POLICY_DIR}/TERRAPIN.pmod" <<'EOF'
# Mitigação Terrapin (CVE-2023-48795)
cipher@SSH = -CHACHA20-POLY1305
ssh_etm = 0
EOF

BASE_POLICY=$(update-crypto-policies --show | cut -d: -f1)
# Remove TERRAPIN duplicado se já aplicado
NEW_POLICY="${BASE_POLICY}:TERRAPIN"
echo "==> Aplicando crypto-policy: ${NEW_POLICY}"
update-crypto-policies --set "${NEW_POLICY}"

# Drop-in defensivo: lista explícita sem ChaCha20 e sem MACs ETM
mkdir -p /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-terrapin.conf <<'EOF'
# Mitigação Terrapin (CVE-2023-48795)
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
EOF

sshd -t
systemctl restart sshd

echo "==> Validação:"
sshd -T | grep -E '^(ciphers|macs) '
if sshd -T | grep -qi 'chacha20-poly1305'; then
  echo "FALHA: chacha20 ainda presente" >&2
  exit 2
fi
if sshd -T | grep -E '^macs ' | grep -qi 'etm@'; then
  echo "FALHA: MAC ETM ainda presente" >&2
  exit 2
fi

echo "OK: mitigação Terrapin aplicada. Recomendado reboot se outros serviços não relerem a crypto-policy."
