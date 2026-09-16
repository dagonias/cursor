# Deploy no Rancher 2.12 — PDS WiFi / Arquiteto NetDevOps Monitor

## Valores já preenchidos

| Item | Valor |
|---|---|
| Namespace | `monitor-wifi` |
| Imagem | `harbor.infraero.gov.br/library/pds_wifi:latest` |
| Service | ClusterIP `pds-wifi` (80 → 5000) |
| Ingress host | `monitor-wifi.infraero.gov.br` |
| TLS secret | `monitor-wifi-tls` (certificado autoassinado) |

> Ajuste o host do Ingress se o DNS interno for outro.

## 1) Credencial do Harbor (se o pull exigir login)

```bash
kubectl create secret docker-registry harbor-creds \
  --namespace monitor-wifi \
  --docker-server=harbor.infraero.gov.br \
  --docker-username=SEU_USUARIO \
  --docker-password=SUA_SENHA \
  --docker-email=seu@email.com
```

Depois descomente `imagePullSecrets` em `deployment.yaml`.

## 2) Aplicar

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
```

No Rancher UI: **Workloads → Create → Import YAML** (cole Deployment, Service e Ingress).

## 3) Validar

```bash
kubectl -n monitor-wifi get pods,svc,ingress
kubectl -n monitor-wifi logs -l app=pds-wifi -f
kubectl -n monitor-wifi describe ingress pds-wifi
```

Acesse: `https://monitor-wifi.infraero.gov.br` (após DNS apontar para o Ingress Controller).

O secret TLS `monitor-wifi-tls` precisa existir no namespace `monitor-wifi` antes do Ingress:

```bash
kubectl -n monitor-wifi get secret monitor-wifi-tls
```

## Notas

- Porta do container: **5000** (Gunicorn)
- `imagePullPolicy: Always` porque a tag é `latest`
- Se a readinessProbe falhar, ajuste o `path` no Deployment para um endpoint real de saúde
- Confirme se o `ingressClassName` do cluster é `nginx` (pode ser `traefik` ou outro)
