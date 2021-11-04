#!/bin/bash

. ./env.sh

axway central delete deployment webhooksite -s $CLUSTER
axway central delete virtualapi webhooksite

axway central apply -f vapi/vapi.yaml
axway central apply -f vapi/releasetag.yaml

cat << EOF > vapi/deployment.yaml
apiVersion: v1alpha1
group: management
kind: Deployment
name: webhooksite
metadata:
  scope:
    kind: Environment
    name: $CLUSTER
tags:
  - v1
spec:
  virtualAPIRelease: webhooksite-1.0.0
  virtualHost: "$CLUSTER.ampgw.sandbox.axwaytest.net"
EOF

axway central apply -f vapi/deployment.yaml