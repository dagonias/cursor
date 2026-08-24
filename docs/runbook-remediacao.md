# Runbook: remediação Nessus — Rancher 2.12 / Rocky Linux 9

Este documento cobre os seis achados do scanner e como eliminá-los no ambiente Rancher.

## Ordem recomendada

1. Backup / janela de manutenção
2. Certificado TLS do Rancher (fecha achados 1, 2 e 3 de uma vez)
3. Terrapin / OpenSSH no host (achado 4)
4. nginx no host + upgrade do cluster / ingress (achados 5 e 6)
5. Novo scan para validar

---

## Achados 1–3 — Certificado SSL

### Causa típica no Rancher

Instalação com certificado **autoassinado** (`ingress.tls.source=rancher`) ou certificado cujo **CN/SAN não inclui o FQDN** usado no acesso (ex.: IP, hostname interno diferente do certificado).

O scanner vê:

- cadeia sem CA pública → “não confiável” / “autoassinado”
- CN ≠ hostname do scan → “wrong hostname”

### Remediação correta

Substituir por certificado emitido por CA pública (DigiCert, Let’s Encrypt, etc.) **ou** CA corporativa já distribuída nos scanners/clientes, com:

- SAN contendo o FQDN exato de acesso ao Rancher (ex.: `rancher.empresa.local`)
- cadeia completa: servidor + intermediárias em `tls.crt`
- chave privada em `tls.key`

#### Passos (cluster local do Rancher)

```bash
# Preparar arquivos
# tls.crt = cert servidor + intermediárias (nessa ordem)
# tls.key = chave privada

kubectl -n cattle-system create secret tls tls-rancher-ingress \
  --cert=tls.crt \
  --key=tls.key \
  --dry-run=client --save-config -o yaml | kubectl apply -f -
```

Se a CA for **privada**, também atualize a CA e o Helm:

```bash
# cacerts.pem = intermediária(s) + root (nessa ordem)
kubectl -n cattle-system create secret generic tls-ca \
  --from-file=cacerts.pem \
  --dry-run=client --save-config -o yaml | kubectl apply -f -

helm get values rancher -n cattle-system -o yaml > values.yaml
# Em values.yaml garantir:
#   ingress.tls.source: secret
#   privateCA: true

helm ls -n cattle-system   # anote a versão
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  -f values.yaml \
  --version <VERSAO_ATUAL>
```

Se a fonte do certificado **não mudou** (já era `secret`), basta reiniciar:

```bash
kubectl rollout restart deploy/rancher -n cattle-system
```

#### Agentes dos clusters downstream

Se mudou a CA (saiu do autoassinado Rancher / mudou CA privada):

```bash
# No cluster local — por ID ou todos os downstream:
./scripts/06-force-redeploy-agents.sh c-xxxxx
./scripts/06-force-redeploy-agents.sh --all
```

Depois, em **Continuous Delivery**, use **Force Update** nos clusters Fleet.

#### Validação

```bash
echo | openssl s_client -connect rancher.empresa.local:443 -servername rancher.empresa.local 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

- Issuer deve ser a CA esperada (não “CN=dynamiclistener-ca” / fake ingress)
- SAN deve incluir o hostname usado no scan
- Clientes/scanners devem confiar na CA

Referência oficial: [Updating the Rancher Certificate (v2.12)](https://ranchermanager.docs.rancher.com/v2.12/getting-started/installation-and-upgrade/resources/update-rancher-certificate).

---

## Achado 4 — SSH Terrapin (CVE-2023-48795)

### Causa

OpenSSH ainda oferece `chacha20-poly1305` e/ou MACs `*-etm@openssh.com` sem mitigação “strict KEX” detectável pelo scanner.

### Remediação no Rocky Linux 9

1. Atualizar pacotes OpenSSH (patch do vendor com strict KEX, quando disponível)
2. Desabilitar algoritmos vulneráveis via **crypto-policies**

```bash
dnf update -y openssh openssh-server openssh-clients

cat >/etc/crypto-policies/policies/modules/TERRAPIN.pmod <<'EOF'
cipher@SSH = -CHACHA20-POLY1305
ssh_etm = 0
EOF

CURRENT=$(update-crypto-policies --show | cut -d: -f1)
update-crypto-policies --set "${CURRENT}:TERRAPIN"
systemctl restart sshd
```

Alternativa (e o que o script `02` também grava) em `/etc/ssh/sshd_config.d/99-terrapin.conf`:

```
Ciphers aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512,hmac-sha2-256,umac-128@openssh.com
```

### Validação

```bash
sshd -T | grep -E '^(ciphers|macs) '
# Não deve listar chacha20-poly1305 nem *-etm@openssh.com
```

Ou use o checker oficial: https://terrapin-attack.com/

---

## Achados 5–6 — nginx vulnerável

O Nessus costuma reportar a **versão anunciada** pelo serviço HTTP. Em ambiente Rancher isso pode ser:

| Origem | O que fazer |
|--------|-------------|
| Pacote `nginx` no Rocky 9 | `dnf update nginx` (ou AppStream / build mais novo) |
| **ingress-nginx / rke2-ingress-nginx** | Upgrade da versão Kubernetes/RKE2 via Rancher (traz controller com nginx embutido atualizado) |
| nginx standalone em outro container | Rebuild/re-tag da imagem |

### CVE-2026-1642 (plugin “nginx 1.3.0 < 1.28.2 / 1.29.x < 1.29.5”)

Corrigido em NGINX OSS **1.28.2** e **1.29.5**. Afeta proxy para upstreams TLS. Correção definitiva = upgrade.

### “nginx < 1.17.7 Information Disclosure”

Indica versão muito antiga reportada. Se o banner ainda for &lt; 1.17.7 após upgrade do host, o tráfego provavelmente vem do **controller de ingress** — atualize o cluster.

### Identificar a origem

```bash
# Host
rpm -q nginx 2>/dev/null || echo "nginx não instalado no host"
curl -sI https://<IP_OU_HOST> | grep -i server

# Cluster (RKE2)
kubectl -n kube-system get pods -l app.kubernetes.io/name=rke2-ingress-nginx -o wide
kubectl -n kube-system get ds -l app.kubernetes.io/name=rke2-ingress-nginx -o yaml | grep -i image:
```

### Upgrade do ingress no Rancher / RKE2

1. **Cluster Management** → editar o cluster → **Kubernetes Version** → escolha release RKE2 recente compatível com Rancher 2.12
2. Aguarde o rolling upgrade dos nós
3. Confirme a imagem do controller:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=rke2-ingress-nginx \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```

Para clusters K3s/Traefik, o “nginx” do scan pode ser outro serviço — confirme com `ss -tlnp` e o header `Server`.

### Pacote no host (Rocky 9)

O AppStream do Rocky 9 pode não ter 1.28.2/1.29.5 imediatamente. Opções:

1. `dnf update nginx` e verificar se o vendor publicou backport do CVE
2. Compilar/empacotar a partir do [nginx.org](https://nginx.org/) (1.28.2 ou 1.29.5+) se o serviço no host for o alvo do scan
3. Se o nginx do host **não** for usado em produção, desabilite/remova o serviço para limpar o finding:

```bash
systemctl disable --now nginx
# ou: dnf remove nginx
```

---

## Checklist pós-remediação

- [ ] `openssl s_client` mostra CA confiável e SAN correto
- [ ] Navegador/scanner não alerta self-signed / hostname mismatch
- [ ] `sshd -T` sem ChaCha20-Poly1305 nem MAC ETM
- [ ] Versão nginx (host e/ou ingress) ≥ 1.28.2 (ou imagem RKE2 atualizada)
- [ ] Novo scan Nessus limpo nos plugins correspondentes
- [ ] Clusters downstream / Fleet reconnectados após troca de CA

## Scripts neste repositório

| Script | Função |
|--------|--------|
| `scripts/01-diagnostico.sh` | Inventário TLS, SSH e nginx |
| `scripts/02-mitigar-terrapin-ssh.sh` | Atualiza OpenSSH + subpolicy TERRAPIN |
| `scripts/03-atualizar-nginx-host.sh` | Atualiza/avalia nginx do SO |
| `scripts/04-aplicar-certificado-rancher.sh` | Aplica `tls-rancher-ingress` (+ migração Helm para `secret`) |
| `scripts/05-verificar-ingress-nginx.sh` | Mostra imagens do ingress e próximos passos |
| `scripts/06-force-redeploy-agents.sh` | Force redeploy dos agents após troca de CA |
