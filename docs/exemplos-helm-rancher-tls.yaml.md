# Exemplos de valores Helm para Rancher 2.12 com certificado próprio

## Certificado de CA pública (DigiCert, Let's Encrypt via secret, etc.)

```yaml
hostname: rancher.empresa.exemplo
ingress:
  tls:
    source: secret
# privateCA: false   # omitir ou false
```

## Certificado de CA corporativa (privada)

```yaml
hostname: rancher.empresa.exemplo
ingress:
  tls:
    source: secret
privateCA: true
```

Aplicar sem mudar a versão do Rancher:

```bash
helm get values rancher -n cattle-system -o yaml > values.yaml
# edite values.yaml
helm ls -n cattle-system   # anote a coluna CHART/APP VERSION
helm upgrade rancher rancher-stable/rancher \
  --namespace cattle-system \
  -f values.yaml \
  --version <MESMA_VERSAO>
```

Secrets necessários em `cattle-system`:

- `tls-rancher-ingress` (tipo TLS) — sempre
- `tls-ca` (generic, chave `cacerts.pem`) — só com CA privada
