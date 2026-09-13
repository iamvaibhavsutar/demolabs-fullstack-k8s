// Scripted pipeline. Builds Maven backend + npm frontend, builds/pushes both
// images with Kaniko (no Docker daemon needed on the agent - matches how
// Jenkins agents run as pods in the kubeadm cluster), then does the GitOps
// handoff: bump the image tag in k8s/ and push to git. No SonarQube stage.
// Argo CD (already watching this repo's k8s/ path, see argocd/application.yaml)
// picks up the commit and syncs it - this Jenkinsfile never runs kubectl apply.

def REGISTRY   = 'docker.io/vsutardevops'
def GIT_REPO   = 'github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git'
def IMAGE_TAG  = ''   // set once we have a build number / short SHA

podTemplate(
  label: 'demolabs-builder',
  containers: [
    containerTemplate(name: 'maven',  image: 'maven:3.9-eclipse-temurin-17', command: 'sleep', args: '99d'),
    containerTemplate(name: 'node',   image: 'node:20-alpine',               command: 'sleep', args: '99d'),
    containerTemplate(name: 'kaniko', image: 'gcr.io/kaniko-project/executor:debug', command: 'sleep', args: '9999999'),
    containerTemplate(name: 'git',    image: 'alpine/git:2.45.2',            command: 'sleep', args: '99d'),
	containerTemplate(
  name: 'docker',
  image: 'docker:27-cli',
  command: 'sleep',
  args: '99d'
),

containerTemplate(
  name: 'dind',
  image: 'docker:27-dind',
  privileged: true,
  envVars: [
    envVar(key: 'DOCKER_TLS_CERTDIR', value: '')
  ],
  command: 'dockerd-entrypoint.sh'
)
  ],
  volumes: [
    // Docker Hub push creds for Kaniko - a docker/config.json built from a
    // Jenkins 'Secret file' credential (see setup steps: "Jenkins credentials").
    secretVolume(secretName: 'dockerhub-dockerconfig', mountPath: '/kaniko/.docker'),
  ]
) {
  node('demolabs-builder') {

    stage('Checkout') {
      checkout scm
      IMAGE_TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
      echo "Building image tag: ${IMAGE_TAG}"
    }

    stage('Build Backend - Maven') {
      container('maven') {
        dir('backend') {
          // -DskipTests: this pipeline is build-only per the requirements;
          // wire a separate 'mvn test' stage back in for a real prod pipeline.
          sh 'mvn -B clean package -DskipTests'
        }
      }
    }

    stage('Build Frontend - npm') {
      container('node') {
        dir('frontend') {
          sh 'npm install'
          sh 'npm run build'
        }
      }
    }

stage('Build & Push Backend Image') {
  container('docker') {
    withEnv([
      'DOCKER_HOST=tcp://localhost:2375',
      'DOCKER_TLS_CERTDIR='
    ]) {
      withCredentials([
        usernamePassword(
          credentialsId: 'dockerhub-creds',
          usernameVariable: 'DOCKER_USER',
          passwordVariable: 'DOCKER_PASS'
        )
      ]) {
        sh """
          echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin

          docker build \
            -t ${REGISTRY}/demolabs-backend:${IMAGE_TAG} \
            -t ${REGISTRY}/demolabs-backend:latest \
            backend

          docker push ${REGISTRY}/demolabs-backend:${IMAGE_TAG}
          docker push ${REGISTRY}/demolabs-backend:latest
        """
      }
    }
  }
}

stage('Build & Push Frontend Image') {
  container('docker') {
    withEnv([
      'DOCKER_HOST=tcp://localhost:2375',
      'DOCKER_TLS_CERTDIR='
    ]) {
      withCredentials([
        usernamePassword(
          credentialsId: 'dockerhub-creds',
          usernameVariable: 'DOCKER_USER',
          passwordVariable: 'DOCKER_PASS'
        )
      ]) {
        sh """
          echo \$DOCKER_PASS | docker login -u \$DOCKER_USER --password-stdin

          docker build \
            -t ${REGISTRY}/demolabs-frontend:${IMAGE_TAG} \
            -t ${REGISTRY}/demolabs-frontend:latest \
            frontend

          docker push ${REGISTRY}/demolabs-frontend:${IMAGE_TAG}
          docker push ${REGISTRY}/demolabs-frontend:latest
        """
      }
    }
  }
}
    stage('Update K8s Manifests & Push (GitOps handoff)') {
      container('git') {
        withCredentials([usernamePassword(credentialsId: 'github-creds', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          sh """
            git config user.email 'ci@demolabs.local'
            git config user.name 'jenkins-ci'

            sed -i "s#${REGISTRY}/demolabs-backend:.*#${REGISTRY}/demolabs-backend:${IMAGE_TAG}#" k8s/06-deploy-backend.yaml
            sed -i "s#${REGISTRY}/demolabs-frontend:.*#${REGISTRY}/demolabs-frontend:${IMAGE_TAG}#" k8s/08-deploy-frontend.yaml

            git add k8s/06-deploy-backend.yaml k8s/08-deploy-frontend.yaml
            git commit -m "ci: bump demolabs images to ${IMAGE_TAG} [skip ci]"
            git push https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO} HEAD:main
          """
        }
      }
    }

    stage('Note') {
      // Deliberately no kubectl/argocd CLI stage here - Argo CD's own
      // automated sync (selfHeal+prune, see argocd/application.yaml) detects
      // the commit above and rolls it out. Jenkins' job ends at "git push".
      echo "Manifests updated to ${IMAGE_TAG}. Argo CD will detect and sync automatically."
    }
  }
}
