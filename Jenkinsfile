pipeline {

    environment {
        REGISTRY = 'harbor.infraero.gov.br'
        registryCredential = 'jenkins-harbor'
        imageName = 'harbor.infraero.gov.br/library/pds_wifi'
        dockerImage = ''

        // ========== SONARQUBE ==========
        // Project Key informado pelo Sonar
        SONAR_PROJECT_KEY = 'pds_wifi_pds_wifi_31921745-1938-4c92-a892-2900c5c9801a'
        // Nome do servidor SonarQube configurado em Jenkins > Manage Jenkins > System
        SONAR_SERVER = 'SonarQube'
        // Nome da instalação do SonarScanner em Jenkins > Global Tool Configuration
        SONAR_SCANNER_TOOL = 'SonarScanner'

        // ========== CONFIGURAÇÕES RANCHER ==========
        K8S_DEPLOYMENT = 'pds-wifi'
        K8S_NAMESPACE = 'monitor-wifi'
        // Nome do container no Deployment (kubectl set image)
        K8S_CONTAINER = 'api'

        DSV_KUBECONFIG = 'rancher-dsv-kubeconfig'
        HML_KUBECONFIG = 'rancher-hml-kubeconfig'
        PRD_KUBECONFIG = 'rancher-prd-kubeconfig'

        PRD_APPROVERS = 'seu-email@infraero.gov.br'
    }

    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout changelog: false,
                poll: false,
                scm: scmGit(
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        credentialsId: 'jenkins-azure',
                        url: 'https://dev.azure.com/InfraeroAeroportos/pds_wifi/_git/pds_wifi'
                    ]]
                )
            }
        }

        // ========== SONAR: análise do código ANTES do build/push ==========
        stage('SonarQube Analysis') {
            steps {
                script {
                    def scannerHome = tool "${SONAR_SCANNER_TOOL}"
                    withSonarQubeEnv("${SONAR_SERVER}") {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                              -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                              -Dsonar.projectName=pds_wifi \
                              -Dsonar.sources=. \
                              -Dsonar.python.version=3.10 \
                              -Dsonar.exclusions=**/venv/**,**/__pycache__/**,**/.git/**,**/k8s/**
                        """
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build') {
            steps {
                script {
                    def IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    imageName = "${imageName}:${IMAGE_TAG}"

                    env.IMAGE_TAG = IMAGE_TAG
                    env.IMAGE_FULL = imageName

                    dockerImage = docker.build(
                        imageName,
                        "-f Dockerfile ."
                    )

                    echo "✅ Imagem construída: ${imageName}"
                }
            }
        }

        stage('Push') {
            steps {
                script {
                    docker.withRegistry(
                        "https://${REGISTRY}",
                        registryCredential
                    ) {
                        dockerImage.push()
                        dockerImage.push("latest")
                        echo "✅ Imagem enviada para Harbor: ${imageName}"
                    }
                }
            }
        }

        stage('Deploy to DSV (Rancher)') {
            steps {
                script {
                    echo "🚀 Deployando em DSV (Desenvolvimento)..."

                    withKubeConfig([credentialsId: "${DSV_KUBECONFIG}"]) {
                        sh """
                            echo "Atualizando deployment ${K8S_DEPLOYMENT} em DSV..."
                            kubectl set image deployment/${K8S_DEPLOYMENT} \
                                ${K8S_CONTAINER}=${env.IMAGE_FULL} \
                                -n ${K8S_NAMESPACE} \
                                --record=true

                            echo "Aguardando rollout em DSV..."
                            kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                --timeout=5m

                            echo "✅ Deploy em DSV concluído!"
                        """
                    }
                }
            }
        }

        stage('Approval for HML') {
            steps {
                script {
                    echo "⏸️ Aguardando aprovação para HOMOLOGAÇÃO..."

                    timeout(time: 5, unit: 'DAYS') {
                        input(
                            message: "Deseja APROVAR para HOMOLOGAÇÃO?\nImagem: ${env.IMAGE_FULL}",
                            ok: 'Aprovar',
                            submitter: null
                        )
                    }

                    echo "✅ Aprovação concedida para HML!"
                }
            }
        }

        stage('Deploy to HML (Rancher)') {
            steps {
                script {
                    echo "🚀 Deployando em HML (Homologação)..."

                    withKubeConfig([credentialsId: "${HML_KUBECONFIG}"]) {
                        sh """
                            echo "Atualizando deployment ${K8S_DEPLOYMENT} em HML..."
                            kubectl set image deployment/${K8S_DEPLOYMENT} \
                                ${K8S_CONTAINER}=${env.IMAGE_FULL} \
                                -n ${K8S_NAMESPACE} \
                                --record=true

                            echo "Aguardando rollout em HML..."
                            kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                --timeout=5m

                            echo "✅ Deploy em HML concluído!"
                        """
                    }
                }
            }
        }

        stage('Request Approval for PRD') {
            steps {
                script {
                    echo "⏸️ Solicitando aprovação para PRODUÇÃO..."

                    timeout(time: 5, unit: 'DAYS') {
                        input(
                            message: "Deseja SOLICITAR aprovação para PRODUÇÃO?\nImagem: ${env.IMAGE_FULL}",
                            ok: 'Solicitar',
                            submitter: null
                        )
                    }

                    echo "✅ Solicitação enviada para PRODUÇÃO!"
                }
            }
        }

        stage('Approval for PRD') {
            steps {
                script {
                    echo "📧 Enviando email de aprovação para PRD..."

                    def COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()

                    def COMMIT_AUTHOR = sh(
                        script: 'git log -1 --pretty=%an',
                        returnStdout: true
                    ).trim()

                    emailext(
                        subject: "🚀 Aprovação PRODUÇÃO: pds_wifi:${env.IMAGE_TAG}",
                        body: """
                            <h2>Solicitação de Aprovação para PRODUÇÃO</h2>
                            <hr>
                            <p><strong>Aplicação:</strong> PDS WiFi</p>
                            <p><strong>Imagem Docker:</strong> <code>${env.IMAGE_FULL}</code></p>
                            <p><strong>Build URL:</strong> <a href="${BUILD_URL}">${BUILD_NUMBER}</a></p>
                            <hr>
                            <h3>Informações do Commit</h3>
                            <p><strong>Autor:</strong> ${COMMIT_AUTHOR}</p>
                            <p><strong>Mensagem:</strong> ${COMMIT_MSG}</p>
                            <hr>
                            <p><strong>⚠️ AÇÃO REQUERIDA:</strong> Clique no link abaixo para aprovar ou rejeitar.</p>
                            <p><a href="${BUILD_URL}input">Acessar Jenkins para Aprovação</a></p>
                        """,
                        to: "${PRD_APPROVERS}",
                        mimeType: 'text/html'
                    )

                    echo "⏸️ Aguardando aprovação dos responsáveis por PRD..."

                    timeout(time: 5, unit: 'DAYS') {
                        input(
                            message: "Deseja APROVAR para PRODUÇÃO?\nImagem: ${env.IMAGE_FULL}",
                            ok: 'Aprovar para PRD',
                            submitter: null
                        )
                    }

                    echo "✅ Aprovação para PRD concedida!"
                }
            }
        }

        stage('Deploy to PRD (Rancher)') {
            steps {
                script {
                    echo "🚀 Deployando em PRD (Produção)..."

                    withKubeConfig([credentialsId: "${PRD_KUBECONFIG}"]) {
                        sh """
                            echo "Atualizando deployment ${K8S_DEPLOYMENT} em PRD..."
                            kubectl set image deployment/${K8S_DEPLOYMENT} \
                                ${K8S_CONTAINER}=${env.IMAGE_FULL} \
                                -n ${K8S_NAMESPACE} \
                                --record=true

                            echo "Aguardando rollout em PRD..."
                            kubectl rollout status deployment/${K8S_DEPLOYMENT} \
                                -n ${K8S_NAMESPACE} \
                                --timeout=5m

                            echo "✅ Deploy em PRD concluído com sucesso!"
                        """
                    }
                }
            }
        }

    }

    post {
        success {
            echo "✅ Pipeline executado com sucesso!"
        }
        failure {
            echo "❌ Pipeline falhou!"
        }
        always {
            echo "🧹 Finalizando..."
        }
    }

}
