# demolabs-fullstack-k8s

A minimal but "prod-shaped" 3-tier app — **React (npm) frontend → Spring Boot (Maven) backend → Postgres**
— containerized and deployed into a `demolabs` namespace on your AWS kubeadm cluster, accessed over
**Tailscale** instead of a public LB (matches how you already reach this cluster: fixed 100.x overlay
IPs on your laptop + all EC2 nodes, since dynamic home/laptop IPs broke SG-based SSH/kubectl access).

Repo: https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git
Registry: Docker Hub, `vsutardevops/demolabs-backend` / `vsutardevops/demolabs-frontend`

```
demolabs-fullstack-k8s/
├── backend/                 # Maven / Spring Boot REST API
│   ├── pom.xml
│   ├── src/main/java/com/demolabs/app/...
│   ├── src/main/resources/application.properties
│   └── Dockerfile
├── frontend/                 # npm / React SPA, served by nginx
│   ├── package.json
│   ├── src/App.js, index.js
│   ├── public/index.html
│   ├── nginx.conf
│   └── Dockerfile
├── db/
│   └── init.sql              # reference copy (real one is baked into a ConfigMap)
├── k8s/                      # all manifests, numbered = apply order
│   ├── 00-namespace.yaml
│   ├── 01-secret-db.yaml
│   ├── 02-configmap.yaml
│   ├── 03-pv-pvc.yaml
│   ├── 04-deploy-db.yaml
│   ├── 05-svc-db.yaml
│   ├── 06-deploy-backend.yaml
│   ├── 07-svc-backend.yaml
│   ├── 08-deploy-frontend.yaml
│   ├── 09-svc-frontend.yaml
│   ├── 10-ingress.yaml
│   ├── 11-hpa.yaml
│   ├── 12-networkpolicy.yaml
│   ├── 13-podpolicy.yaml
│   └── 14-poddisruptionbudget.yaml
└── deploy.sh
```

---

## 1. What each piece is and why

**App layer**
- `backend/` — Spring Boot REST API (`/api/tasks`, `/api/ping`), JPA + Postgres driver, Actuator
  exposed for k8s probes (`management.endpoint.health.probes.enabled=true` splits health into
  **liveness** and **readiness** sub-states — that split is what the probes below hook into).
- `frontend/` — React SPA built to static files, served by nginx. nginx also **reverse-proxies
  `/api/*` to the backend Service** so the browser only ever talks to one origin (no CORS, no
  hardcoded backend hostname baked into the JS bundle).
- `db/init.sql` — creates the `tasks` table and seeds one row on first boot.

**Dockerfiles** — both are multi-stage: a heavy build stage (Maven/npm + full JDK/Node) produces the
artifact, then a slim runtime stage (JRE-alpine / nginx-alpine) actually ships. Keeps images small
and keeps build tooling out of the attack surface. Both run as **non-root** — required by the
`restricted` Pod Security level set on the namespace.

**K8s manifests**
| File | Kind | Purpose |
|---|---|---|
| `00-namespace.yaml` | Namespace | Creates `demolabs`; labels it for Pod Security Admission (`restricted`) |
| `01-secret-db.yaml` | Secret | Postgres credentials (base64, not encryption — see note below) |
| `02-configmap.yaml` | ConfigMap ×3 | DB name, backend's `DB_HOST/PORT/NAME`, and the SQL init script |
| `03-pv-pvc.yaml` | PV + PVC | Static hostPath volume for Postgres data (see storage note below) |
| `04/05` | Deployment + Service | Postgres — `Recreate` strategy (RWO volume can't be double-mounted), `pg_isready` probes |
| `06/07` | Deployment + Service | Backend — 2 replicas, Actuator-based probes, resource requests (needed for HPA) |
| `08/09` | Deployment + Service | Frontend — 2 replicas, `/healthz` probe (doesn't depend on backend being up) |
| `10-ingress.yaml` | Ingress | Routes `demolabs.local` → frontend Service |
| `11-hpa.yaml` | HPA ×2 | Scales backend 2→6, frontend 2→4 on CPU% |
| `12-networkpolicy.yaml` | NetworkPolicy | Default-deny + explicit allow: ingress→frontend→backend→db, plus DNS egress |
| `13-podpolicy.yaml` | (see note) | PSP replacement — PSA label (mandatory, already active) + optional Kyverno example |
| `14-poddisruptionbudget.yaml` | PDB ×2 | `minAvailable: 1` so node drains don't take a whole tier down |

**Storage note:** I used a static `hostPath` PV instead of a StorageClass/dynamic provisioning,
because your kubeadm cluster has no cloud-provider CSI plugin wired up (it's not EKS — you're running
kubeadm on plain EC2s). Run `mkdir -p /mnt/data/demolabs-postgres` on whichever node the pod lands on
before first deploy, or switch it to an EBS-CSI StorageClass if you've since installed that driver.

**"nodepolicy" / "podpolicy" naming note:** Kubernetes doesn't have literal resources called
`NodePolicy`/`PodPolicy`. I mapped these to what they mean in real clusters:
- **NodePolicy → `NetworkPolicy`** (enforced by Calico, which your cluster already runs)
- **PodPolicy → PodSecurityPolicy's replacement.** PSP was removed in k8s 1.25; your cluster is
  1.31.14, so the PSP API genuinely doesn't exist to apply. What actually enforces "no privileged
  pods" today is the **Pod Security Admission** label on the namespace (already wired in
  `00-namespace.yaml`) — the Kyverno policy in `13-podpolicy.yaml` is an optional extra layer, not
  required for this stack to run.

**Secrets note:** `Secret` objects are base64-**encoded**, not encrypted — anyone with `get secrets`
RBAC in `demolabs` can read the password in plaintext. Fine for this learning project; for anything
closer to real production, route this through Sealed Secrets or SOPS instead of committing
plaintext-decodable values, and don't commit `01-secret-db.yaml` to a public repo as-is.

---

## 2. Build, push, deploy

```bash
# Backend
cd backend
docker build -t vsutardevops/demolabs-backend:1.0.0 .
docker push vsutardevops/demolabs-backend:1.0.0

# Frontend
cd ../frontend
docker build -t vsutardevops/demolabs-frontend:1.0.0 .
docker push vsutardevops/demolabs-frontend:1.0.0
```
The image paths in `k8s/06-deploy-backend.yaml` and `k8s/08-deploy-frontend.yaml` already point at
`docker.io/vsutardevops/...` — bump the tag there (or let the Jenkinsfile do it, see
`SETUP-CICD.md`) whenever you push a new version, then:

```bash
mkdir -p /mnt/data/demolabs-postgres   # on the node the DB pod will land on
./deploy.sh
```

---

## 3. Access URL — over Tailscale, not a public LB

You don't have a public-facing LB/domain here — access goes over the Tailscale mesh (fixed 100.x
overlay IPs on your laptop and every node in your kubeadm cluster). Two ways to reach the app, pick one:

**A. Ingress-nginx as NodePort (simplest)**
```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
# note the NodePort mapped to 80, e.g. 31780
```
On your laptop, add to `/etc/hosts` using the **Tailscale IP of whichever node runs the ingress
controller** (run `tailscale ip -4` on that node to get it):
```
100.x.x.x   demolabs.local
```
Then browse to:
```
http://demolabs.local:31780/
```

**B. Skip Ingress entirely, NodePort the frontend Service directly**
```bash
kubectl -n demolabs patch svc demolabs-frontend-svc -p '{"spec":{"type":"NodePort"}}'
kubectl -n demolabs get svc demolabs-frontend-svc   # note the NodePort
```
```
http://<any-node-tailscale-100.x-ip>:<nodeport>/
```

Either way, nothing here is reachable except over Tailscale — no security group opened, no dynamic-IP
breakage next time your home/laptop IP changes.

---

## 4. Troubleshooting runbook — break each component on purpose, then fix it

Do these one at a time against a healthy `./deploy.sh` baseline. Each one is a realistic prod incident.

### Incident 1 — DB: wrong PVC binding (`Pending` pods)
**Break it:**
```bash
kubectl -n demolabs patch pv demolabs-postgres-pv -p '{"spec":{"storageClassName":"wrong-class"}}'
kubectl -n demolabs delete pod -l app=demolabs-postgres
```
**Symptom:** `kubectl -n demolabs get pods` shows Postgres stuck `Pending`.
**Diagnose:**
```bash
kubectl -n demolabs describe pod -l app=demolabs-postgres   # Events: "no persistent volumes available for this claim"
kubectl get pv demolabs-postgres-pv                          # STATUS: Available, but storageClassName mismatch
```
**Root cause:** PVC requests `storageClassName: demolabs-local`; PV now advertises `wrong-class` —
they no longer match on the selector, so the PVC can't bind.
**Fix:**
```bash
kubectl -n demolabs patch pv demolabs-postgres-pv -p '{"spec":{"storageClassName":"demolabs-local"}}'
```

### Incident 2 — DB credentials drift (`CrashLoopBackOff`)
**Break it:**
```bash
kubectl -n demolabs patch secret demolabs-db-secret -p '{"data":{"POSTGRES_PASSWORD":"d3JvbmdwYXNz"}}'
kubectl -n demolabs rollout restart deploy/demolabs-postgres
```
**Symptom:** Postgres container restarts repeatedly.
**Diagnose:**
```bash
kubectl -n demolabs logs deploy/demolabs-postgres --previous
# "password authentication failed" or PGDATA re-init conflict if a volume with the OLD password persists
```
**Root cause:** the PVC already has a Postgres data directory initialized with the *old* password;
changing the Secret doesn't retroactively change the DB user's actual password on disk.
**Fix:** revert the Secret to the original value (changing a live DB's password has to go through
`ALTER USER`, not just editing the k8s Secret):
```bash
kubectl -n demolabs patch secret demolabs-db-secret -p '{"data":{"POSTGRES_PASSWORD":"ZGVtb2xhYnMxMjM="}}'
kubectl -n demolabs rollout restart deploy/demolabs-postgres
```

### Incident 3 — Backend can't reach DB (`CrashLoopBackOff` / readiness failing)
**Break it:**
```bash
kubectl -n demolabs patch configmap demolabs-backend-config -p '{"data":{"DB_HOST":"wrong-svc-name"}}'
kubectl -n demolabs rollout restart deploy/demolabs-backend
```
**Symptom:** backend pods `Running` but `0/1 Ready`, `/actuator/health/readiness` returns DOWN.
**Diagnose:**
```bash
kubectl -n demolabs logs deploy/demolabs-backend
# UnknownHostException: wrong-svc-name
kubectl -n demolabs get endpoints demolabs-postgres-svc   # confirms real svc name/existence
```
**Root cause:** ConfigMap `DB_HOST` no longer matches the actual Service name (`demolabs-postgres-svc`)
— classic "someone renamed the Service, forgot the ConfigMap" drift.
**Fix:**
```bash
kubectl -n demolabs patch configmap demolabs-backend-config -p '{"data":{"DB_HOST":"demolabs-postgres-svc"}}'
kubectl -n demolabs rollout restart deploy/demolabs-backend
```

### Incident 4 — NetworkPolicy too strict (silent timeout, not an error)
**Break it:**
```bash
kubectl -n demolabs delete networkpolicy allow-backend-egress-to-db
```
**Symptom:** backend readiness flips to DOWN, but *no* log line about auth or wrong host — just
connection timeouts. This is the annoying one: app-level logs look identical to "DB is down."
**Diagnose:**
```bash
kubectl -n demolabs get networkpolicy
kubectl -n demolabs exec deploy/demolabs-backend -- nc -zv demolabs-postgres-svc 5432   # times out
# Postgres itself is healthy: kubectl -n demolabs get pods -l app=demolabs-postgres  -> Running/Ready
```
**Root cause:** default-deny-all is active; without the explicit backend→db egress rule, Calico drops
the packets before they leave the backend pod. Nothing logs an "error" because the connection never
gets a response to time out gracefully against.
**Fix:**
```bash
kubectl -n demolabs apply -f k8s/12-networkpolicy.yaml   # re-applies the allow-backend-egress-to-db rule
```

### Incident 5 — Frontend → backend proxy misconfigured (`502` in browser)
**Break it:**
```bash
kubectl -n demolabs patch svc demolabs-backend-svc -p '{"spec":{"ports":[{"port":9090,"targetPort":8080}]}}'
```
(nginx.conf's `proxy_pass` hardcodes port 8080; Service now front-ends on 9090.)
**Symptom:** page loads (frontend is healthy), but "Add task" / task list fails with 502.
**Diagnose:**
```bash
kubectl -n demolabs exec deploy/demolabs-frontend -- curl -sv http://demolabs-backend-svc:8080/api/ping
# curl: (7) Failed to connect - port 8080 refused, service now listens on 9090
kubectl -n demolabs get svc demolabs-backend-svc -o yaml   # confirms the port drift
```
**Root cause:** Service port changed without updating nginx.conf's `proxy_pass` target — a
frontend/backend contract break, the most common real "who touched the Service port" incident.
**Fix:** revert the Service (in prod: also add a contract test / integration check to CI so a port
change trips a pipeline failure, not a runtime 502):
```bash
kubectl -n demolabs patch svc demolabs-backend-svc -p '{"spec":{"ports":[{"port":8080,"targetPort":8080}]}}'
```

### Incident 6 — HPA stuck at `<unknown>` (no metrics)
**Break it:**
```bash
kubectl -n demolabs patch deploy demolabs-backend --type=json \
  -p='[{"op":"remove","path":"/spec/template/spec/containers/0/resources/requests"}]'
```
**Symptom:** `kubectl -n demolabs get hpa` shows `TARGETS: <unknown>/70%` forever, never scales.
**Diagnose:**
```bash
kubectl -n demolabs describe hpa demolabs-backend-hpa
# "missing request for cpu" in Conditions
```
**Root cause:** HPA CPU% is computed as usage ÷ **requested** CPU — no `resources.requests.cpu` means
no denominator, so the controller can't compute a percentage at all (this is *separate* from whether
metrics-server itself is even installed — check that too with `kubectl top pods -n demolabs`).
**Fix:** restore the `resources` block from `k8s/06-deploy-backend.yaml`:
```bash
kubectl -n demolabs apply -f k8s/06-deploy-backend.yaml
```

### Incident 7 — PDB blocks a node drain (real maintenance-window incident)
**Break it (simulate a drain with only 1 replica up):**
```bash
kubectl -n demolabs scale deploy demolabs-backend --replicas=1
kubectl drain <node-running-that-pod> --ignore-daemonsets --delete-emptydir-data
```
**Symptom:** `drain` hangs / errors with `Cannot evict pod as it would violate the pod's disruption budget`.
**Diagnose:**
```bash
kubectl -n demolabs get pdb demolabs-backend-pdb   # ALLOWED DISRUPTIONS: 0
```
**Root cause:** PDB requires `minAvailable: 1`; with only 1 replica running, evicting it would drop
you to 0 — PDB is doing exactly its job and refusing.
**Fix:** scale back up before draining (the PDB is correct; the runbook step order was wrong):
```bash
kubectl -n demolabs scale deploy demolabs-backend --replicas=2
kubectl uncordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

### Incident 8 — Wrong probe path (`CrashLoopBackOff` from a healthy app)
**Break it:**
```bash
kubectl -n demolabs patch deploy demolabs-backend --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/wrong-path"}]'
```
**Symptom:** app logs show it started fine, but the pod still restarts every ~45–60s.
**Diagnose:**
```bash
kubectl -n demolabs describe pod -l app=demolabs-backend
# Liveness probe failed: HTTP probe failed with statuscode: 404
```
**Root cause:** probe path doesn't exist on the app — kubelet kills a perfectly healthy container
because *the probe itself* is misconfigured, not the app. Very common after someone renames an
Actuator endpoint or moves to a custom health path without updating the manifest.
**Fix:**
```bash
kubectl -n demolabs apply -f k8s/06-deploy-backend.yaml
```

---

## 5. Quick health check after any fix
```bash
kubectl -n demolabs get pods,svc,hpa,pdb,networkpolicy
kubectl -n demolabs exec deploy/demolabs-frontend -- curl -s http://demolabs-backend-svc:8080/api/ping
curl -s http://demolabs.local:<nodeport>/api/tasks
```
