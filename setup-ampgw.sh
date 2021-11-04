#!/bin/bash

. ./env.sh

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
EOF

helm delete ampgw --wait
helm install ampgw ampc-rel/ampgw -f override.yaml --wait

echo ============================
echo === Waiting for all Pods ===
echo ============================
echo Turn off your VPN
kubectl wait --timeout 10m --for=condition=Complete jobs --all

