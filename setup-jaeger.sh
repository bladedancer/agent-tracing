#!/bin/sh

. ./env.sh

echo ========================
echo === Deploying Jaeger ===
echo ========================

kubectl create namespace observability
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/crds/jaegertracing.io_jaegers_crd.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/service_account.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/role_binding.yaml
kubectl create -n observability -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/operator.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/cluster_role.yaml
kubectl create -f https://raw.githubusercontent.com/jaegertracing/jaeger-operator/master/deploy/cluster_role_binding.yaml

echo ============================
echo === Waiting for all Pods ===
echo ============================
echo "Disable VPN if it's running"
kubectl wait --timeout 10m --for=condition=Ready pods --all --all-namespaces

kubectl apply -n observability -f - <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: $CLUSTER
EOF

kubectl get -n observability ingress

echo =====================================================================
echo = To access this from outside of WSL2 you need to forward the ports =
echo =====================================================================
K8_INGRESS=$(kubectl describe -n kube-system service/traefik | grep "LoadBalancer Ingress" | awk "{print \$3}" | sed "s/,//")
echo "RUN: sudo socat TCP-LISTEN:80,fork,reuseaddr TCP:$K8_INGRESS:80"