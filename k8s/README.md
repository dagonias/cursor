# Deploy no Rancher 2.12 — Arquiteto NetDevOps Monitor
#
# Pré-requisitos:
# - Namespace já criado no cluster
# - Imagem já publicada no Harbor (via Jenkins)
# - kubectl apontando para o cluster (ou use a UI do Rancher)

## 1) Preencha os placeholders

Nos arquivos em `k8s/`, substitua:

| Placeholder | Exemplo |
|---|---|
| `SUBSTITUA_PELO_SEU_NAMESPACE` | `netdevops` |
| `SUBSTITUA_PELA_IMAGEM_HARBOR` | `harbor.empresa.com/netdevops/arquiteto-monitor:1.0.0` |
| `SUBSTITUA_PELO_SEU_DOMINIO` | `arquiteto-monitor.empresa.local` (só no Ingress) |

## 2) Credencial do Harbor (se o pull exigir login)

```bash
kubectl create secret docker-registry harbor-creds \
  --namespace SEU_NAMESPACE \
  --docker-server=harbor.empresa.com \
  --docker-username=SEU_USUARIO \
  --docker-password=SUA_SENHA \
  --docker-email=seu@email.com
```

Depois descomente `imagePullSecrets` em `deployment.yaml`.

## 3) Aplicar no cluster

Pelo kubectl:

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Só se precisar de URL externa:
kubectl apply -f k8s/ingress.yaml
```

Pelo Rancher UI:

1. Cluster → Project/Namespace
2. Workloads → Create → Import YAML
3. Cole o conteúdo de `deployment.yaml` e `service.yaml`
4. (Opcional) Import YAML do `ingress.yaml`

## 4) Validar

```bash
kubectl -n SEU_NAMESPACE get pods,svc,ingress
kubectl -n SEU_NAMESPACE logs -l app=arquiteto-netdevops-monitor -f
kubectl -n SEU_NAMESPACE port-forward svc/arquiteto-netdevops-monitor 8080:80
```

Abra `http://localhost:8080` no navegador.

## Notas

- Porta do container: **5000** (Gunicorn)
- Service interno: porta **80** → container **5000**
- 1 réplica é suficiente para dashboard de consulta
- Workers BSB/H3C já sobem via `entrypoint.sh` dentro do mesmo pod
- Se a readinessProbe falhar (path `/` inexistente), ajuste o `path` no `deployment.yaml` para um endpoint real de saúde
