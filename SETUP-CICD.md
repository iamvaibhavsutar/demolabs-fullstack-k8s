# CI/CD setup for demolabs — what to create, where, how, and why

This wires up: **Jenkins builds + pushes images (Kaniko) → commits new image tag to git →
Argo CD notices the git change and syncs it into the cluster.** Jenkins never touches the
cluster directly — think of Jenkins as a chef who cooks a dish and puts it on the pass
(git), and Argo CD as the waiter who only serves what's on the pass, not whatever the chef
hands them directly across the kitchen. That separation is the whole point of GitOps: one
system (Argo CD) has cluster write-access, and it only acts on what's committed.

Repo: `https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git`
Registry: Docker Hub, user `vsutardevops`

Do these **in order** — each step depends on the one before it.

---

## Step 1 — Push the project to GitHub (source of truth for code + manifests)

**Why:** Argo CD only knows how to watch a git repo/path. Until this exists, nothing else
in this list has anywhere to point at.

**UI (GitHub):** github.com → + → New repository → name `demolabs-fullstack-k8s` →
Visibility Private (or Public, your call for a learning project) → Create repository.
(You've already done this — repo exists at the URL above.)

**CLI:**
```bash
cd devops-demolabs-stack
git init
git remote add origin https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git
git add -A
git commit -m "initial commit: demolabs app + k8s manifests"
git branch -M main
git push -u origin main
```

---

## Step 2 — Create a Docker Hub access token (image registry credentials)

**Why:** Kaniko (which builds and pushes your images from inside the Jenkins pod, no
Docker daemon needed) needs push credentials. Docker Hub's equivalent of a scoped
service-account is a **personal access token** with a specific permission level — use one
instead of your actual account password anywhere in Jenkins, so if it ever leaks you can
revoke just that token without changing your real login. Real-world analogy: it's a
spare key you can cancel any time, not the one key that opens everything you own.

**UI:** hub.docker.com → your avatar → Account Settings → Security → New Access Token →
description `jenkins-ci` → permissions **Read & Write** → Generate → **copy the token
immediately** (shown once).

**CLI:** Docker Hub doesn't expose token creation over a public API for personal
accounts — do this one in the UI.

---

## Step 3 — Put the Docker Hub credentials into a Kubernetes Secret (for Kaniko)

**Why:** the Jenkinsfile's `podTemplate` mounts a Secret named `dockerhub-dockerconfig`
at `/kaniko/.docker/config.json` — that's how Kaniko authenticates to push, without the
Jenkinsfile ever containing a password in plaintext.

**Where:** in whichever namespace your Jenkins agent pods actually run (commonly `jenkins`
— check Manage Jenkins → Clouds → Kubernetes → Pod Templates → Namespace).

**CLI (no UI equivalent — this is a cluster-side secret, not a Jenkins or Docker Hub setting):**
```bash
kubectl create secret docker-registry dockerhub-dockerconfig \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=vsutardevops \
  --docker-password='<paste the access token from Step 2>' \
  --docker-email=<your-dockerhub-email> \
  -n jenkins
```

---

## Step 4 — Add a Jenkins credential for git push access

**Why:** the pipeline's last build stage commits an updated image tag and pushes it back
to GitHub — it needs a token with write access, referenced by the credential ID
`github-creds` used in the Jenkinsfile's `withCredentials` block.

**First, on the GitHub side:** Settings → Developer settings → Personal access tokens →
Fine-grained tokens → Generate new token → Repository access: only
`demolabs-fullstack-k8s` → Permissions: **Contents: Read and write** → Generate → copy
the token.

**UI (Jenkins):** Manage Jenkins → Credentials → System → Global credentials (unrestricted)
→ Add Credentials → Kind: "Username with password" → Username: `iamvaibhavsutar` →
Password: `<the GitHub token>` → ID: `github-creds` (must match the Jenkinsfile exactly)
→ Create.

**CLI (Jenkins CLI, if you prefer scripting it):**
```bash
java -jar jenkins-cli.jar -s http://<your-jenkins-host>/ \
  -auth admin:$JENKINS_ADMIN_TOKEN create-credentials-by-xml system::system::jenkins _ <<'EOF'
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <id>github-creds</id>
  <username>iamvaibhavsutar</username>
  <password>TOKEN</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF
```
(For a one-off, the UI path is far less fiddly than hand-building this XML.)

---

## Step 5 — Create the Jenkins Pipeline job

**Why:** this is what actually runs the `Jenkinsfile` on a trigger.

**UI:** Dashboard → New Item → name `demolabs-ci` → type "Pipeline" → OK. In the job
config: Pipeline section → Definition: "Pipeline script from SCM" → SCM: Git → Repository
URL: `https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git` → Credentials: (a
read credential for GitHub, separate from `github-creds` if you want read/write split) →
Branch: `*/main` → Script Path: `Jenkinsfile` → Save.

**CLI (REST API, using a minimal job-config.xml):**
```bash
curl -X POST "http://<your-jenkins-host>/createItem?name=demolabs-ci" \
  --user admin:$JENKINS_ADMIN_TOKEN \
  -H "Content-Type: application/xml" \
  --data-binary @job-config.xml
```

---

## Step 6 (optional but recommended) — GitHub webhook so pushes auto-trigger Jenkins

**Why:** without this, the job only runs when someone clicks "Build Now" or Jenkins polls
git on a timer (slower feedback, wastes poll cycles). Only useful if your Jenkins is
reachable from GitHub's servers — for a home/personal Jenkins behind Tailscale/NAT with no
public endpoint, skip this and just trigger builds manually or poll SCM on a schedule
instead.

**UI:** GitHub repo → Settings → Webhooks → Add webhook → Payload URL:
`http://<your-public-jenkins-host>/github-webhook/` → Content type: `application/json` →
"Just the push event" → Add webhook.

---

## Step 7 — Register the app with Argo CD

**Why:** this is the object that actually makes Argo CD watch `k8s/` in this repo and
auto-sync it into the `demolabs` namespace. Nothing deploys until this exists.

**UI (Argo CD):** + New App → Application Name: `demolabs` → Project: `default` →
Sync Policy: **Automatic**, tick **Prune Resources** and **Self Heal** → Repository URL:
`https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git` → Revision: `main` →
Path: `k8s` → Cluster URL: `https://kubernetes.default.svc` → Namespace: `demolabs` →
Create.

**CLI (either works — pick one):**
```bash
kubectl apply -f argocd/application.yaml
# or, using the argocd CLI directly:
argocd app create demolabs \
  --repo https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git \
  --path k8s \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace demolabs \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

If the repo is **private**, Argo CD also needs its own read credential for GitHub before
it can even see it:
```bash
argocd repo add https://github.com/iamvaibhavsutar/demolabs-fullstack-k8s.git \
  --username iamvaibhavsutar \
  --password '<a GitHub PAT with at least read access to this repo>'
```

---

## Step 8 — First run

Push to `main` (or click "Build Now" on `demolabs-ci`). Watch it happen:
```bash
# Jenkins side
curl -s http://<your-jenkins-host>/job/demolabs-ci/lastBuild/consoleText

# Argo CD side, once Jenkins has pushed a manifest-tag-bump commit
argocd app get demolabs
argocd app sync demolabs --dry-run   # sanity check before it auto-syncs, if you want to look first
kubectl -n demolabs get pods -w
```

**Why check both sides separately:** if Jenkins is green but nothing changes in the
cluster, the break is almost always the Argo CD Application pointing at the wrong
path/branch, or the git push in the last Jenkins stage silently failing on auth — checking
them independently tells you which half of the pipeline to debug (see `README.md` §4 for
the same kind of split-the-problem-in-half diagnosis applied to the app itself).

---

## Quick reference — everything created, at a glance

| What | Where it lives | Why it exists |
|---|---|---|
| `demolabs-fullstack-k8s` repo | GitHub | single source of truth for app code + manifests |
| Docker Hub access token (`vsutardevops`) | Docker Hub | scoped, revocable image push/pull credential |
| Secret `dockerhub-dockerconfig` | k8s, Jenkins agent namespace | lets Kaniko push without a Docker daemon or plaintext creds in the Jenkinsfile |
| Credential `github-creds` | Jenkins | lets the pipeline push the manifest-tag-bump commit |
| Pipeline job `demolabs-ci` | Jenkins | runs `Jenkinsfile` on trigger |
| Webhook (optional) | GitHub → Jenkins | push-triggers builds instead of relying on polling |
| Application `demolabs` | Argo CD (`argocd` namespace) | watches `k8s/` in git, auto-syncs into `demolabs` namespace |
