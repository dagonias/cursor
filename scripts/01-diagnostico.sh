#!/usr/bin/env bash
# Diagnóstico read-only: TLS Rancher, SSH Terrapin, nginx (host + cluster).
set -euo pipefail

echo "=== Host ==="
hostnamectl --static 2>/dev/null || hostname
cat /etc/rocky-release 2>/dev/null || cat /etc/os-release | head -5
echo

echo "=== OpenSSH (Terrapin) ==="
rpm -q openssh-server openssh 2>/dev/null || true
if command -v sshd >/dev/null 2>&1; then
  echo "-- ciphers/macs efetivos --"
  sshd -T 2>/dev/null | grep -E '^(ciphers|macs) ' || true
  if sshd -T 2>/dev/null | grep -qi 'chacha20-poly1305'; then
    echo "ALERTA: chacha20-poly1305 ainda habilitado (Terrapin)"
  else
    echo "OK: chacha20-poly1305 não listado"
  fi
  if sshd -T 2>/dev/null | grep -E '^macs ' | grep -qi 'etm@'; then
    echo "ALERTA: MAC ETM ainda habilitado (Terrapin)"
  else
    echo "OK: MACs ETM não listados"
  fi
fi
echo "-- crypto-policy --"
update-crypto-policies --show 2>/dev/null || true
echo

echo "=== nginx no host ==="
if rpm -q nginx >/dev/null 2>&1; then
  rpm -q nginx
  nginx -v 2>&1 || true
  systemctl is-active nginx 2>/dev/null || true
  systemctl is-enabled nginx 2>/dev/null || true
else
  echo "Pacote nginx não instalado no host"
fi
echo

echo "=== Banner HTTP local (se algo escuta 80/443) ==="
for port in 80 443; do
  if ss -tln | grep -q ":${port} "; then
    echo "-- porta ${port} --"
    if [[ "$port" == "443" ]]; then
      curl -skI --max-time 5 "https://127.0.0.1:${port}/" 2>/dev/null | head -15 || true
    else
      curl -sI --max-time 5 "http://127.0.0.1:${port}/" 2>/dev/null | head -15 || true
    fi
  fi
done
echo

echo "=== Cluster Kubernetes (se kubectl disponível) ==="
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  echo "-- ingress Rancher --"
  kubectl -n cattle-system get ingress 2>/dev/null || true
  kubectl -n cattle-system get secret tls-rancher-ingress -o yaml 2>/dev/null \
    | grep -E '^(  name:|  type:)' || echo "Secret tls-rancher-ingress não encontrado"
  echo "-- certificado atual (se secret existir) --"
  if kubectl -n cattle-system get secret tls-rancher-ingress >/dev/null 2>&1; then
    kubectl -n cattle-system get secret tls-rancher-ingress -o jsonpath='{.data.tls\.crt}' \
      | base64 -d 2>/dev/null \
      | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true
  fi
  echo "-- Helm Rancher (tls source) --"
  if command -v helm >/dev/null 2>&1; then
    helm get values rancher -n cattle-system 2>/dev/null | grep -A5 -E 'tls:|privateCA|hostname' || true
  fi
  echo "-- rke2 / ingress-nginx images --"
  kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' 2>/dev/null \
    | grep -iE 'ingress-nginx|nginx-ingress' || echo "Nenhum pod ingress-nginx encontrado"
else
  echo "kubectl indisponível ou cluster inacessível neste host"
fi

echo
echo "Diagnóstico concluído. Veja docs/runbook-remediacao.md para os próximos passos."
