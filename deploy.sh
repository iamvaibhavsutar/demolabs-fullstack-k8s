#!/usr/bin/env bash
# Apply order matters: namespace -> secret/config -> storage -> workloads -> policies
set -euo pipefail
K=./k8s

kubectl apply -f $K/00-namespace.yaml
kubectl apply -f $K/01-secret-db.yaml
kubectl apply -f $K/02-configmap.yaml
kubectl apply -f $K/03-pv-pvc.yaml
kubectl apply -f $K/04-deploy-db.yaml
kubectl apply -f $K/05-svc-db.yaml
kubectl apply -f $K/06-deploy-backend.yaml
kubectl apply -f $K/07-svc-backend.yaml
kubectl apply -f $K/08-deploy-frontend.yaml
kubectl apply -f $K/09-svc-frontend.yaml
kubectl apply -f $K/10-ingress.yaml
kubectl apply -f $K/11-hpa.yaml
kubectl apply -f $K/12-networkpolicy.yaml
kubectl apply -f $K/13-podpolicy.yaml || echo "skip: kyverno not installed"
kubectl apply -f $K/14-poddisruptionbudget.yaml

echo "Waiting for rollout..."
kubectl -n demolabs rollout status deploy/demolabs-postgres
kubectl -n demolabs rollout status deploy/demolabs-backend
kubectl -n demolabs rollout status deploy/demolabs-frontend
