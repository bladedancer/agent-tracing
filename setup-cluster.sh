#!/bin/bash

echo ===============================
echo === Create Cluster $CLUSTER ===
echo ===============================

. ./env.sh

k3d cluster delete $CLUSTER
k3d cluster create --kubeconfig-update-default=false --volume $PWD:$PWD --servers 3 --timeout=10m --wait $CLUSTER
export KUBECONFIG=$(k3d kubeconfig write $CLUSTER)
kubectl cluster-info

echo ========================
echo === Configure docker ===
echo ========================
kubectl create secret generic regcred \
    --from-file=.dockerconfigjson=$HOME/.docker/config.json \
    --type=kubernetes.io/dockerconfigjson

echo "RUN:"
echo "export KUBECONFIG=$(k3d kubeconfig write $CLUSTER)"