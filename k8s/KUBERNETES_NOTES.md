# Kubernetes Notes

## What is Kubernetes?

Kubernetes is a **container orchestrator** — it manages containers automatically across multiple machines.

You declare **what you want**:
> "Run 3 copies of myapp, always keep them running, restart if one crashes"

Kubernetes figures out **how to make it happen**.

### Analogy
Like a restaurant manager — you say "keep 3 waiters on shift", the manager handles hiring, scheduling, and replacements. You don't micromanage.

---

## Core Concepts

### Pod
The smallest unit in Kubernetes. A pod runs one or more containers.

### Deployment
Manages pods. Ensures the desired number of replicas are always running.

### Service
A stable network address for your pods. Pods come and go, but the Service always routes traffic to whatever pod is running.

### Resource Types Format
```bash
kubectl <command> <resource-type>/<resource-name>
# Examples:
kubectl get deployment/myapp
kubectl get pod/myapp-abc123
kubectl get service/myapp-service
```

---

## Scaling

```bash
# Scale up to 3 replicas
kubectl scale deployment myapp --replicas=3

# Check pods
kubectl get pods -l app=myapp

# Watch pods in real time
kubectl get pods -l app=myapp -w
```

**Key insight:** Scaling is fast after the first deployment because the image is already cached on the node.

---

## Self Healing

Kubernetes automatically restarts crashed pods. Try it:

```bash
# Delete a pod to simulate a crash
kubectl delete pod <pod-name>

# Kubernetes immediately creates a replacement
kubectl get pods -l app=myapp
```

The Deployment constantly watches and enforces: *"I need X replicas running at all times."*

---

## Rollbacks

```bash
# View rollout history
kubectl rollout history deployment/myapp

# Roll back to previous version
kubectl rollout undo deployment/myapp

# Roll back to a specific revision
kubectl rollout undo deployment/myapp --to-revision=1
```

> **Warning:** Rollbacks can be risky — you might roll back to a broken version. Always check what the previous revision contained.

---

## ConfigMaps

Stores **non-sensitive** configuration outside your Docker image. Change config without rebuilding the image.

```bash
# Create a ConfigMap
kubectl create configmap myapp-config \
  --from-literal=SERVER_PORT=8081 \
  --from-literal=APP_ENV=development

# View it
kubectl get configmap myapp-config
kubectl describe configmap myapp-config
```

### Inject into Deployment (deployment.yaml)
```yaml
containers:
  - name: myapp
    envFrom:
      - configMapRef:
          name: myapp-config
```

### Verify inside pod
```bash
kubectl exec -it <pod-name> -- env
```

---

## Secrets

Stores **sensitive** data (passwords, API keys). Values are hidden from `kubectl describe`.

```bash
# Create a Secret
kubectl create secret generic myapp-secret \
  --from-literal=DB_PASSWORD=supersecret123 \
  --from-literal=API_KEY=abc123xyz

# View it (values are hidden, only size shown)
kubectl describe secret myapp-secret
```

### Inject into Deployment (deployment.yaml)
```yaml
containers:
  - name: myapp
    envFrom:
      - configMapRef:
          name: myapp-config
      - secretRef:
          name: myapp-secret
```

### ConfigMap vs Secret

| | ConfigMap | Secret |
|---|---|---|
| Use for | Ports, feature flags, env names | Passwords, API keys, tokens |
| Values visible | Yes | No (only size shown) |
| Encoded | No | Base64 |

---

## Liveness & Readiness Probes

### What they do
- **Liveness probe** — is the app alive? If not, restart the pod
- **Readiness probe** — is the app ready for traffic? If not, remove from load balancer

### Setup (requires Spring Boot Actuator)
Add to `pom.xml`:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

Health endpoints:
- `http://<url>/actuator/health` — overall health
- `http://<url>/actuator/health/liveness` — liveness
- `http://<url>/actuator/health/readiness` — readiness

### Add to deployment.yaml
```yaml
containers:
  - name: myapp
    livenessProbe:
      httpGet:
        path: /actuator/health/liveness
        port: 8081
      initialDelaySeconds: 30
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /actuator/health/readiness
        port: 8081
      initialDelaySeconds: 30
      periodSeconds: 10
```

### Rolling update behaviour
```
Old pod: 1/1 Running  ← still serving traffic
New pod: 0/1 Running  ← readiness probe waiting (30s)
New pod: 1/1 Running  ← probe passed, now receiving traffic
Old pod: Terminating  ← safely removed
```
This is **zero downtime deployment**.

---

## Resource Limits

Prevents one app from consuming all CPU/memory on a node.

```yaml
containers:
  - name: myapp
    resources:
      requests:
        cpu: "250m"      # Reserved for scheduling
        memory: "256Mi"
      limits:
        cpu: "500m"      # Maximum allowed
        memory: "512Mi"
```

| | Requests | Limits |
|---|---|---|
| Purpose | Reserved for scheduling | Maximum allowed |
| If exceeded | N/A | CPU throttled, Memory → pod killed |

> `250m` = 250 millicores = 0.25 of one CPU core

```bash
# Verify limits are applied
kubectl describe pod -l app=myapp
```

---

## Namespaces

Isolates resources within a cluster. Resources in one namespace can't automatically see resources in another.

```bash
# View all namespaces
kubectl get namespaces

# Create a namespace
kubectl create namespace staging

# Deploy into a specific namespace
kubectl apply -f k8s/ -n staging

# View resources in a namespace
kubectl get all -n staging
kubectl get pods -n staging

# Delete entire namespace (deletes everything inside)
kubectl delete namespace staging
```

### Built-in namespaces
| Namespace | Purpose |
|---|---|
| `default` | Where your app lives |
| `kube-system` | Kubernetes system components |
| `kube-public` | Publicly readable data |
| `kube-node-lease` | Node heartbeat tracking |

### Key rule
ConfigMaps and Secrets do NOT copy across namespaces — you must create them in each namespace separately.

### Real world usage
| Approach | When |
|---|---|
| One cluster, multiple namespaces | Small teams |
| Separate cluster per environment | Large companies (more isolation) |

---

## Service Types

| Type | Accessible from | Use case |
|---|---|---|
| `ClusterIP` | Inside cluster only | Internal service-to-service communication |
| `NodePort` | Outside cluster via node port (30000-32767) | Local development |
| `LoadBalancer` | Public IP via cloud load balancer | Production on AWS/GCP/Azure |

---

## Ingress

A smart router at the front of your cluster. One entry point that routes to multiple services based on hostname or path.

```
Browser → Ingress (port 80) → Service → Pod
```

vs NodePort:
```
Browser → NodePort:30080 → Service → Pod
```

### Example ingress.yaml
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-service
                port:
                  number: 8081
```

```bash
# Apply ingress
kubectl apply -f k8s/ingress.yaml

# Check ingress
kubectl get ingress
kubectl describe ingress myapp-ingress
```

### Access on Windows (Minikube Docker driver)
Minikube's IP is not directly reachable on Windows because it runs inside WSL2. Use port-forward instead:

```bash
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80
```

Add to hosts file (PowerShell as Administrator):
```powershell
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "127.0.0.1 myapp.local"
```

Then access: `http://myapp.local:8080`

---

## Useful Commands Reference

```bash
# Get resources
kubectl get pods
kubectl get services
kubectl get deployments
kubectl get configmaps
kubectl get secrets
kubectl get ingress
kubectl get all

# Describe (detailed info + events)
kubectl describe pod <name>
kubectl describe deployment <name>

# Logs
kubectl logs <pod-name>
kubectl logs -l app=myapp --tail=50

# Exec into pod
kubectl exec -it <pod-name> -- sh
kubectl exec -it <pod-name> -- env

# Apply/delete manifests
kubectl apply -f k8s/
kubectl delete -f k8s/

# Scale
kubectl scale deployment myapp --replicas=3

# Rollout
kubectl rollout status deployment/myapp
kubectl rollout history deployment/myapp
kubectl rollout undo deployment/myapp

# Watch in real time
kubectl get pods -w
```
