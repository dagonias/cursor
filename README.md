# PDS WiFi / Arquiteto NetDevOps Monitor

API/dashboard Python (Gunicorn na porta 5000) com workers BSB e H3C.

## Deploy no Rancher

- Namespace: `monitor-wifi`
- Imagem: `harbor.infraero.gov.br/library/pds_wifi:latest`
- Manifestos em [`k8s/`](./k8s/) — guia em [`k8s/README.md`](./k8s/README.md)

## Pipeline Jenkins + SonarQube

Arquivos: [`Jenkinsfile`](./Jenkinsfile) e [`sonar-project.properties`](./sonar-project.properties)

Ordem: Checkout → **SonarQube + Quality Gate** → Build → Push Harbor → Deploy DSV/HML/PRD

O scanner roda via Docker (`sonarsource/sonar-scanner-cli`) — **não precisa** da Global Tool `SonarScanner`.

Peça ao admin do Jenkins apenas se falhar:
1. Servidor SonarQube cadastrado com o nome `SonarQube` (ou o nome real usado aí)
2. Webhook do Sonar → `https://SEU_JENKINS/sonarqube-webhook/` (Quality Gate)
3. Se o agent não puxar do Docker Hub, espelhar a imagem do scanner no Harbor e alterar `SONAR_SCANNER_IMAGE`
