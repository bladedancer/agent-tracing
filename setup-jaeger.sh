#!/bin/sh

. ./env.sh

kubectl create namespace observability

echo ==============================
echo === Deploying Cert Manager ===
echo ==============================
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.0/cert-manager.yaml
kubectl wait --timeout 10m --for=condition=Ready pods --all -n cert-manager

echo ========================================
echo === Deploying OpenTelemetry Operator ===
echo ========================================
curl -Lso opentelemetry-operator.yaml https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
sed -i "s#cert-manager.io/v1alpha2#cert-manager.io/v1#" ./opentelemetry-operator.yaml
kubectl apply -f ./opentelemetry-operator.yaml

kubectl wait --timeout 10m --for=condition=Ready pods --all -n opentelemetry-operator-system

kubectl apply -n observability -f - <<EOF
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: $CLUSTER-ot
spec:
  config: |
    receivers:
      otlp:
        protocols:
          grpc:
          http:
    processors:

    exporters:
      logging:

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: []
          exporters: [logging]
EOF

echo ========================
echo === Deploying Jaeger ===
echo ========================

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
kubectl wait --timeout 10m --for=condition=Ready pods --all -n observability

kubectl apply -n observability -f - <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: $CLUSTER-jaeger
EOF

kubectl get -n observability ingress

echo =====================================================================
echo = To access this from outside of WSL2 you need to forward the ports =
echo =====================================================================
K8_INGRESS=$(kubectl describe -n kube-system service/traefik | grep "LoadBalancer Ingress" | awk "{print \$3}" | sed "s/,//")
echo "RUN: sudo socat TCP-LISTEN:80,fork,reuseaddr TCP:$K8_INGRESS:80"