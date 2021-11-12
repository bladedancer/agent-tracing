#!/bin/bash

. ./env.sh


echo ================================
echo === Bootstraping images      ===
echo ================================
docker pull axway.jfrog.io/ampc-docker-release-ptx/ampgw-install-axway-cli:0.4.0  
k3d image import --cluster $CLUSTER axway.jfrog.io/ampc-docker-release-ptx/ampgw-install-axway-cli:0.4.0
k3d image import --cluster $CLUSTER ampc-docker-snapshot-ptx.artifactory-ptx.ecd.axway.int/ampgw-governance-agent:0.5.0-POC-0012-SNAPSHOT

echo ================================
echo === Creating Service Account ===
echo ================================

openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -pubout -in private_key.pem -out public_key.pem -outform pem
axway --env $PLATFORM_ENV service-account remove $CLUSTER 
ACC=$(axway --env $PLATFORM_ENV service-account create --name $CLUSTER --public-key ./public_key.pem --json --role api_central_admin)
CLIENT_ID=$(echo $ACC | jq -r .client.client_id)
ORG_ID=$(echo $ACC | jq -r .org.id)

echo ==============================
echo === Creating Listener Cert ===
echo ==============================
openssl req -x509 -newkey rsa:4096 -keyout listener_private_key.pem -nodes -out listener_certificate.pem -days 365 -subj '/CN=*.ampgw.com/O=Axway/C=IE'

echo =============================
echo === Creating AmpGw Secret ===
echo =============================
kubectl delete secret ampgw-secret
kubectl create secret generic ampgw-secret \
    --from-file serviceAccPrivateKey=private_key.pem \
    --from-file serviceAccPublicKey=public_key.pem \
    --from-file listenerPrivateKey=listener_private_key.pem  \
    --from-file listenerCertificate=listener_certificate.pem \
    --from-literal orgId=$ORG_ID \
    --from-literal clientId=$CLIENT_ID

echo ============================
echo === Installing Dataplane ===
echo ============================
CREDS=$(cat ~/.docker/config.json | jq -r '.auths."axway.jfrog.io".auth' | base64 -d)
IFS=':'
read -a userpass <<< "$CREDS"
helm repo add --force-update ampc-rel https://axway.jfrog.io/artifactory/ampc-helm-release --username ${userpass[0]} --password ${userpass[1]}

cat << EOF > override.yaml
global:
  environment: $CLUSTER
  listenerPort: 8443
  exposeProxyAdminPort: true
  proxyAdminPort: 9001

imagePullSecrets:
  - name: regcred
ampgw-governance-agent:
  imagePullSecrets: 
    - name: regcred
  readinessProbe:
    timeoutSeconds: 5
  livenessProbe:
    timeoutSeconds: 5
  env:
    CENTRAL_AUTH_URL: $CENTRAL_AUTH_URL
    CENTRAL_URL: $CENTRAL_URL
    CENTRAL_USAGEREPORTING_URL: $CENTRAL_USAGEREPORTING_URL
    CENTRAL_DEPLOYMENT: $CENTRAL_DEPLOYMENT
    CENTRAL_PLATFORM_URL: $CENTRAL_PLATFORM_URL
    TRACEABILITY_HOST: $TRACEABILITY_HOST
    TRACEABILITY_PROTOCOL: $TRACEABILITY_PROTOCOL
    TRACEABILITY_REDACTION_PATH_SHOW: "$TRACEABILITY_REDACTION_PATH_SHOW"
    TRACEABILITY_REDACTION_QUERYARGUMENT_SHOW: "$TRACEABILITY_REDACTION_QUERYARGUMENT_SHOW"
    TRACEABILITY_REDACTION_REQUESTHEADER_SHOW: "$TRACEABILITY_REDACTION_REQUESTHEADER_SHOW"
    TRACEABILITY_REDACTION_RESPONSEHEADER_SHOW: "$TRACEABILITY_REDACTION_RESPONSEHEADER_SHOW"

provisioning:
  platformEnv: $PLATFORM_ENV
  centralUrl: $CENTRAL_URL

ampgw-proxy:
  imagePullSecrets:
    - name: regcred

  # HACK FOR NOW TO ADD OT-CLUSTER
  templates:
    envoy.yaml: |-
      node:
        cluster: ampgw
        id: ampgw

      admin:
        address:
          socket_address:
            address: 0.0.0.0
            port_value: 9901

      dynamic_resources:
        ads_config:
          api_type: GRPC
          transport_api_version: V3
          grpc_services:
          - envoy_grpc:
              cluster_name: agent-cluster
          set_node_on_first_message_only: true
        cds_config:
          resource_api_version: V3
          ads: {}
        lds_config:
          resource_api_version: V3
          ads: {}
          
      static_resources:
        clusters:
        - connect_timeout: 1s
          type: LOGICAL_DNS
          load_assignment:
            cluster_name: agent-cluster
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: ampgw-governance-agent
                      port_value: 18000
          http2_protocol_options: {}
          name: agent-cluster
        - connect_timeout: 1s
          type: LOGICAL_DNS
          load_assignment:
            cluster_name: ot-cluster
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: tracing-ot-collector.observability.svc.cluster.local
                      port_value: 4317
          http2_protocol_options: {}
          name: ot-cluster
        - connect_timeout: 1s
          type: LOGICAL_DNS
          load_assignment:
            cluster_name: jaeger-cluster
            endpoints:
            - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: tracing-jaeger-collector.observability.svc.cluster.local
                      port_value: 9411
          http2_protocol_options: {}
          name: jaeger-cluster
EOF

helm delete ampgw --wait
helm install ampgw ampc-rel/ampgw -f override.yaml --wait

echo ============================
echo === Waiting for all Pods ===
echo ============================
echo Turn off your VPN
kubectl wait --timeout 10m --for=condition=Complete jobs --all

