# PDS WiFi / Arquiteto NetDevOps Monitor

API/dashboard Python (Gunicorn na porta 5000) com workers BSB e H3C.

## Deploy no Rancher

- Namespace: `monitor-wifi`
- Imagem: `harbor.infraero.gov.br/library/pds_wifi:latest`
- Manifestos em [`k8s/`](./k8s/) — guia em [`k8s/README.md`](./k8s/README.md)

## Pipeline Jenkins + SonarQube

Arquivos: [`Jenkinsfile`](./Jenkinsfile) e [`sonar-project.properties`](./sonar-project.properties)

Ordem: Checkout → **SonarQube + Quality Gate** → Build → Push Harbor → Deploy DSV/HML/PRD

O Jenkins **não tem** o plugin SonarQube (`withSonarQubeEnv` indisponível). A pipeline usa:
- Docker `sonarsource/sonar-scanner-cli`
- Credencial Secret text `jenkins-sonar` (token do Sonar)
- Quality Gate via API REST (`curl`)

### O que você precisa configurar (sem ser admin global)

1. Confirmar a URL: `SONAR_HOST_URL` (hoje `https://sonar.infraero.gov.br`)
2. Criar no job/pasta uma credencial **Secret text**:
   - ID: `jenkins-sonar`
   - Valor: token de usuário do SonarQube com acesso ao projeto
3. Se o agent não puxar do Docker Hub, espelhar o scanner no Harbor e alterar `SONAR_SCANNER_IMAGE`
