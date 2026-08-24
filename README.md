# Hardening Rancher 2.12 em Rocky Linux 9

Runbook e scripts para remediar achados típicos de scanner (Nessus) em nós Rocky Linux 9 com Rancher 2.12:

| # | Achado | Categoria |
|---|--------|-----------|
| 1–3 | Certificado SSL não confiável / hostname incorreto / autoassinado | TLS do Rancher |
| 4 | SSH Terrapin (CVE-2023-48795) | OpenSSH no host |
| 5–6 | nginx desatualizado (CVE-2026-1642 e disclosure antigo) | nginx no host e/ou ingress-nginx |

## Uso rápido

```bash
# 1) Diagnóstico (não altera nada)
sudo ./scripts/01-diagnostico.sh

# 2) Mitigar Terrapin + atualizar OpenSSH
sudo ./scripts/02-mitigar-terrapin-ssh.sh

# 3) Atualizar nginx instalado no SO (se existir)
sudo ./scripts/03-atualizar-nginx-host.sh

# 4) Aplicar certificado TLS confiável no Rancher
#    (requer tls.crt + tls.key; cacerts.pem se CA privada)
./scripts/04-aplicar-certificado-rancher.sh /caminho/tls.crt /caminho/tls.key

# 5) Se a CA mudou: forçar redeploy dos agents
./scripts/06-force-redeploy-agents.sh --all

# 6) Verificar / orientar upgrade do ingress-nginx (RKE2/K3s)
./scripts/05-verificar-ingress-nginx.sh
```

Documentação detalhada: [`docs/runbook-remediacao.md`](docs/runbook-remediacao.md).
