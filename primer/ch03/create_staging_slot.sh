#!/bin/bash

PASS=$(az acr credential show -n $ACR -o tsv --query passwords[0].value)

az webapp deployment slot create \
    -g $RG_CH03 \
    -n ${RG_CH03}-disphostname \
    -s staging \
    --configuration-source ${RG_CH03}-disphostname

az webapp config container set \
    -g $RG_CH03 \
    -n ${RG_CH03}-disphostname \
    -s staging \
    --docker-custom-image-name ${ACR}.azurecr.io/disp-hostname:0.0.2 \
    --docker-registry-server-url ${ACR}.azurecr.io \
    --docker-registry-server-user $ACR \
    --docker-registry-server-password $PASS
