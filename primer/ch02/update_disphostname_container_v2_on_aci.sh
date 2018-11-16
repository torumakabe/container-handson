#!/bin/bash

PASS=$(az acr credential show -n $ACR -o tsv --query passwords[0].value)

az container create \
    -g $RG_CH02 \
    -n ${RG_CH02}-disphostname \
    --registry-login-server ${ACR}.azurecr.io \
    --registry-username ${ACR} \
    --registry-password $PASS \
    --image ${ACR}.azurecr.io/disp-hostname:0.0.2 \
    --ip-address public