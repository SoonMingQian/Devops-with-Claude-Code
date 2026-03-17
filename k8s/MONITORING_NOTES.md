# Monitoring Notes (Prometheus + Grafana)

## How it works

```
App exposes metrics → Prometheus scrapes → Grafana visualizes → Alertmanager notifies
```

- **Logs** — text messages describing what happened (`ERROR: connection failed`)
- **Metrics** — numbers over time (`http_requests_total = 342`)
- Prometheus uses **metrics**, not logs

### How Prometheus scrapes your app

Your app exposes an HTTP endpoint `/actuator/prometheus`. Prometheus visits it every few seconds and pulls the numbers. This is called **scraping** (pull model).

---

## App Setup (Spring Boot)

Add to `pom.xml`:
```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

Add to `application.properties`:
```properties
management.endpoints.web.exposure.include=health,info,prometheus
```

This exposes `/actuator/prometheus` with metrics in Prometheus format.

---

## Install Prometheus + Grafana with Helm

```bash
# Add the Helm chart repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install the full monitoring stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

# Verify all pods are running
kubectl get pods -n monitoring
```

**What gets deployed:**
| Pod | Purpose |
|---|---|
| `prometheus-...` | Scrapes and stores metrics |
| `grafana-...` | Dashboards and visualization |
| `alertmanager-...` | Routes alerts to notifications |
| `kube-state-metrics-...` | Exposes Kubernetes object metrics |
| `node-exporter-...` | Exposes node CPU/memory/disk metrics |

> **Helm key insight:** One command deploys an entire production-grade monitoring stack.
> Helm manages third-party apps. Your own app's integration (ServiceMonitor) you still write yourself.

---

## Access Grafana

```bash
# Port-forward Grafana to localhost
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Open `http://localhost:3000`

Get the admin password:
```bash
# PowerShell
$pass = kubectl get secret -n monitoring prometheus-grafana -o jsonpath="{.data.admin-password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($pass))
```

Default username: `admin`

---

## ServiceMonitor — Connect Prometheus to Your App

Prometheus uses **service discovery** via labels to find apps. A `ServiceMonitor` tells it where to scrape.

Namespaces are just for organization — Prometheus can scrape across namespaces.

### Step 1: Name the port in `service.yaml`

```yaml
ports:
  - name: http
    port: 8081
    targetPort: 8081
    nodePort: 30080
```

### Step 2: Create `k8s/service-monitor.yaml`

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-monitor
  namespace: monitoring
  labels:
    release: prometheus
spec:
  namespaceSelector:
    matchNames:
      - default
  selector:
    matchLabels:
      app: myapp
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 15s
```

```bash
kubectl apply -f k8s/service-monitor.yaml
```

**Key labels:**
- `release: prometheus` — tells Prometheus operator to pick this up
- `namespaceSelector` — allows cross-namespace scraping (monitoring → default)
- `selector.matchLabels` — finds your service by label `app: myapp`

---

## Access Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
```

Open `http://localhost:9090`

- `/targets` — see all scrape targets and their status
- `/alerts` — see all alert rules and their state

---

## PromQL — Querying Metrics

```promql
# Is app up? (1 = up, 0 = down)
up{job="myapp-service"}

# HTTP request count
http_server_requests_seconds_count{job="myapp-service"}

# All metrics from your app
{job="myapp-service"}
```

> **Note:** The job name comes from the Service name, not the ServiceMonitor name.

---

## Grafana — Build a Dashboard Panel

1. Click **+** → **New Dashboard** → **Add visualization**
2. Select **Prometheus** as data source
3. Click **Code** button (top right of query editor) to enter raw PromQL
4. Paste your query and click **Run queries**

---

## Alerting with PrometheusRule

Create `k8s/prometheus-rule.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: monitoring
  labels:
    release: prometheus
spec:
  groups:
    - name: myapp
      rules:
        - alert: MyAppDown
          expr: absent(up{job="myapp-service"}) or up{job="myapp-service"} == 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "myapp is down"
            description: "myapp has been unreachable for more than 1 minute."
```

```bash
kubectl apply -f k8s/prometheus-rule.yaml
```

### Alert lifecycle

```
Inactive → Pending (condition true but < 1m) → Firing
```

### Why `absent()` matters

- `up == 0` only fires if the metric exists but equals 0
- When app is completely down, Prometheus drops the target — the metric disappears entirely
- `absent()` catches this case — fires when the metric doesn't exist at all
- **Production rule:** Always use `absent() or up == 0`, never just `up == 0`

### Test the alert

```bash
# Take app down
kubectl scale deployment myapp --replicas=0

# Watch http://localhost:9090/alerts — goes Inactive → Pending → Firing

# Bring app back
kubectl scale deployment myapp --replicas=1
```

---

## Alertmanager — Email Notifications

### Why Alertmanager is separate from Prometheus

| Problem | Alertmanager handles it |
|---|---|
| Same alert fires 100 times in 1 minute | **Grouping** — sends 1 notification, not 100 |
| App flaps up/down repeatedly | **Inhibition** — suppresses repeat alerts |
| Maintenance window | **Silencing** — mute alerts temporarily |

Prometheus detects problems. Alertmanager decides who to notify, how, and when.

### Configure email notifications via Helm

Create `jenkins/alertmanager-values.yaml`:
```yaml
alertmanager:
  config:
    global:
      smtp_smarthost: 'smtp.gmail.com:587'
      smtp_from: 'sender@gmail.com'
      smtp_auth_username: 'sender@gmail.com'
      smtp_auth_password: 'YOUR_GMAIL_APP_PASSWORD'
      smtp_require_tls: true

    route:
      group_by: ['alertname']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 1h
      receiver: 'email-alert'
      routes:
        - matchers:
            - alertname = "Watchdog"
          receiver: 'null'

    receivers:
      - name: 'null'
      - name: 'email-alert'
        email_configs:
          - to: 'receiver@gmail.com'
            send_resolved: true
```

> **Gmail:** Use an App Password, not your regular password.
> Go to Google Account → Security → 2-Step Verification → App passwords.

Apply with Helm:
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --reuse-values \
  -f jenkins/alertmanager-values.yaml
```

### Access Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093
```

Open `http://localhost:9093`

Check actual rendered config (what Alertmanager really uses):
```bash
kubectl exec -n monitoring alertmanager-prometheus-kube-prometheus-alertmanager-0 -- \
  sh -c 'cat /etc/alertmanager/config_out/alertmanager.env.yaml'
```

Check all alerts via API:
```
http://localhost:9093/api/v2/alerts
```

### Common gotchas

**Must explicitly define `null` receiver:**
```yaml
receivers:
  - name: 'null'   # ← required even though null is built-in
  - name: 'email-alert'
    ...
```
If missing, Prometheus Operator throws: `undefined receiver "null" used in route` and falls back to default config (everything goes to null).

**Verify Operator reconciled successfully:**
```bash
kubectl get alertmanager -n monitoring prometheus-kube-prometheus-alertmanager -o yaml
# Look for: type: Reconciled / status: "True"
```

**`send_resolved: true`** — sends a second email when the alert clears, not just when it fires.

---

## What's Next

- **Custom metrics** — add business-level metrics to your app (e.g. count `/hello` calls)
- **Grafana dashboards** — build a multi-panel health dashboard for your app
