#!/bin/sh

export CLUSTER=tracing
export KUBECONFIG=$(k3d kubeconfig write $CLUSTER)

export PLATFORM_ENV=preprod
export CENTRAL_AUTH_URL=https://login-preprod.axway.com/auth
export CENTRAL_URL=https://gmatthews.dev.ampc.axwaytest.net
export CENTRAL_USAGEREPORTING_URL=https://lighthouse-staging.admin.staging.appctest.com
export CENTRAL_DEPLOYMENT=teams
export CENTRAL_PLATFORM_URL=https://platform.axwaytest.net
export TRACEABILITY_HOST=ingestion.condor.staging.axwaytest.net:5044
export TRACEABILITY_PROTOCOL=tcp
export TRACEABILITY_REDACTION_PATH_SHOW=[{keyMatch:".*"}]
export TRACEABILITY_REDACTION_QUERYARGUMENT_SHOW=[{keyMatch:".*"}]
export TRACEABILITY_REDACTION_REQUESTHEADER_SHOW=[{keyMatch:".*"}]
export TRACEABILITY_REDACTION_RESPONSEHEADER_SHOW=[{keyMatch:".*"}]

axway --env $PLATFORM_ENV auth login 

axway central config set --platform=$PLATFORM_ENV
axway central config set --baseUrl=$CENTRAL_URL
