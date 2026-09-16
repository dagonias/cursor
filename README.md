# PDS WiFi / Arquiteto NetDevOps Monitor

API/dashboard Python (Gunicorn na porta 5000) com workers BSB e H3C.

## Deploy no Rancher

- Namespace: `monitor-wifi`
- Imagem: `harbor.infraero.gov.br/library/pds_wifi:latest`
- Manifestos em [`k8s/`](./k8s/) — guia em [`k8s/README.md`](./k8s/README.md)

## Pipeline Jenkins + SonarQube

Arquivos: [`Jenkinsfile`](./Jenkinsfile) e [`sonar-project.properties`](./sonar-project.properties)

Ordem: Checkout → **SonarQube + Quality Gate** → Build → Push Harbor → Deploy DSV/HML/PRD

No Jenkins, confira:
1. Servidor SonarQube com o nome `SonarQube` (Manage Jenkins → System)
2. Tool `SonarScanner` instalada (Global Tool Configuration)
3. Webhook do SonarQube apontando para `https://SEU_JENKINS/sonarqube-webhook/` (necessário para Quality Gate)
