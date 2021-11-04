#!/bin/sh

. ./env.sh
./setup-cluster.sh
./setup-jaeger.sh
./setup-ampgw.sh
./setup-vapi.sh

echo "RUN:"
echo "export KUBECONFIG=$(k3d kubeconfig write tracing)"
