# DevOps Pipeline CI/CD

## Overview

A hands-on DevOps practice project that implements a full CI/CD pipeline using Git, Jenkins, Docker, a private container registry, and Kubernetes. The project uses a simple Spring Boot web application as the workload to exercise the complete pipeline end-to-end.

Jenkins is self-hosted (running in a Docker container or on a VM). The private registry is a self-hosted Docker Registry (registry:2) running locally or on the same host as Jenkins. Kubernetes is a local cluster (Minikube or kind) used for deployment.

## Goals

- Practice building a real CI/CD pipeline from source commit to running container in Kubernetes
- Understand each stage of the pipeline: code push → build → test → containerize → push to registry → deploy
- Learn how Jenkins, Docker, and Kubernetes integrate in a real workflow
- Build confidence with Jenkinsfile-as-code, Docker image tagging, and Kubernetes manifests

## Tech Stack

| Layer | Tool / Technology |
|---|---|
| Source Control | Git (local repo or GitHub) |
| CI Server | Jenkins (self-hosted, Dockerized) |
| Containerization | Docker |
| Private Registry | Self-hosted Docker Registry (`registry:2`) |
| Orchestration | Kubernetes (Minikube or kind) |
| App Runtime | Spring Boot (simple REST API, Java 21) |
| Build Tool | Maven (`mvn`) |
| Image Build | Dockerfile |
| K8s Config | YAML manifests (Deployment + Service) |

## Project Structure

```
devops-pipeline-cicd/
├── app/                        # Application source code
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/example/myapp/
│   │   │   │   └── MyAppApplication.java   # Spring Boot entry point
│   │   │   └── resources/
│   │   │       └── application.properties
│   │   └── test/
│   │       └── java/com/example/myapp/
│   │           └── MyAppApplicationTests.java
│   ├── pom.xml
│   └── Dockerfile              # Builds the app container image
├── jenkins/
│   ├── Jenkinsfile             # Declarative pipeline definition
│   └── docker-compose.yml      # Runs Jenkins + registry locally
├── k8s/
│   ├── deployment.yaml         # Kubernetes Deployment manifest
│   └── service.yaml            # Kubernetes Service manifest (NodePort or LoadBalancer)
└── CLAUDE.md
```

## Pipeline / Workflow

The pipeline is triggered by a push to the `main` branch and runs the following stages in order:

```
Git Push (main)
    └─► Jenkins detects change (poll SCM or webhook)
            └─► Stage: Checkout
                    └─► Stage: Build & Test
                            └─► Stage: Docker Build
                                    └─► Stage: Push to Private Registry
                                            └─► Stage: Deploy to Kubernetes
```

### Stage Details

1. **Checkout** - Jenkins pulls the latest code from Git.
2. **Build & Test** - Runs `mvn test` inside the workspace. Fail fast: if tests fail, the pipeline stops here.
3. **Docker Build** - Builds the image tagged with the Jenkins build number:
   `localhost:5000/myapp:${BUILD_NUMBER}` (also tags `:latest`).
4. **Push to Private Registry** - Pushes both tags to the local registry at `localhost:5000`.
5. **Deploy to Kubernetes** - Updates the Deployment image using `kubectl set image` or applies an updated manifest. Uses `kubectl rollout status` to confirm the rollout succeeds.

## Key Commands

### Start the local infrastructure
```bash
# Start Jenkins and private registry
cd jenkins/
docker-compose up -d

# Verify registry is up
curl http://localhost:5000/v2/_catalog

# Access Jenkins UI
open http://localhost:8080
```

### Build and push image manually (for debugging)
```bash
# Build
docker build -t localhost:5000/myapp:latest ./app

# Push to private registry
docker push localhost:5000/myapp:latest

# Verify image is in registry
curl http://localhost:5000/v2/myapp/tags/list
```

### Kubernetes commands
```bash
# Start Minikube (if using Minikube)
minikube start

# Allow Minikube to pull from local registry
minikube addons enable registry-creds
# OR use an insecure registry flag: minikube start --insecure-registry="localhost:5000"

# Apply manifests
kubectl apply -f k8s/

# Check rollout
kubectl rollout status deployment/myapp

# Check running pods
kubectl get pods -l app=myapp

# View app logs
kubectl logs -l app=myapp --tail=50

# Get service URL (Minikube)
minikube service myapp-service --url
```

### Trigger / monitor a pipeline run
```bash
# Jenkins pipeline can be triggered via UI or by pushing to main
git push origin main

# Watch Jenkins build log from CLI (requires Jenkins CLI jar)
java -jar jenkins-cli.jar -s http://localhost:8080 console <job-name> <build-number>
```

### Teardown
```bash
kubectl delete -f k8s/
docker-compose -f jenkins/docker-compose.yml down
minikube stop
```

## Conventions & Constraints

### Git
- `main` is the pipeline trigger branch. Push to `main` to kick off a build.
- Use feature branches for changes; merge to `main` when ready to deploy.
- Commit messages: use imperative mood, e.g. `Add health check endpoint`, `Fix Dockerfile base image`.

### Docker
- Image naming convention: `localhost:5000/myapp:<BUILD_NUMBER>` and `localhost:5000/myapp:latest`.
- The registry runs without TLS (insecure) for local practice. Docker daemon must have `localhost:5000` listed in `insecure-registries` in `/etc/docker/daemon.json`.
- Do not push images larger than necessary — use a slim base image (e.g. `eclipse-temurin:21-jre-alpine`).

### Jenkinsfile
- The pipeline is **declarative** (not scripted). Keep it in `jenkins/Jenkinsfile` at the repo root or symlinked.
- Environment variables (registry URL, app name) are defined at the top of the Jenkinsfile so they are easy to change.
- Credentials (if any) must be stored in Jenkins Credentials Manager, not hardcoded in the Jenkinsfile.

### Kubernetes
- Manifests live in `k8s/`. All resources use the label `app: myapp` for consistent selection.
- The Deployment always pulls the image tagged with the specific build number, not `:latest`, so rollbacks are deterministic.
- Do not modify `k8s/deployment.yaml` image tags by hand — the pipeline owns that.

### Things Claude should NOT do without asking
- Do not change the Kubernetes namespace from `default` without confirming — this project keeps everything in `default` for simplicity.
- Do not switch the registry from the local self-hosted one to Docker Hub or another external registry without confirming.
- Do not add new pipeline stages or restructure the Jenkinsfile without confirming the intent first.
- Do not delete or recreate the Minikube cluster; use `kubectl rollout undo` for rollbacks.
- Do not enable TLS on the local registry without asking — the insecure setup is intentional for this learning environment.

## Notes

- **Insecure registry**: Because the local registry runs over HTTP, both Docker and Minikube need to be told to trust it. If image pulls fail in Kubernetes, this is the first thing to check.
- **Jenkins first-run setup**: On first start, retrieve the initial admin password with `docker exec <jenkins-container> cat /var/jenkins_home/secrets/initialAdminPassword`.
- **kubectl context**: Make sure `kubectl` is pointing at the local cluster (`kubectl config current-context`) before running deploy commands — avoid accidentally deploying to a real cluster.
- **Port reference**: Jenkins UI → `8080`, Private Registry → `5000`, App (NodePort) → `30080` (configurable in `k8s/service.yaml`).

## Learning Preferences
- Socratic Method: If I ask for a fix, first ask me what I think the error means based on the logs.
- Verification Steps: After every automated action (like a kubectl apply), suggest a manual check command I can run to verify the result myself.