#!/bin/bash

PASS=$(az acr credential show -n $ACR -o tsv --query passwords[0].value)

az appservice plan create \
    -g $RG_CH03 \
    -n ${RG_CH03}-appsvcplan \
    --sku S1 \
    --is-linux

az webapp create \
    -g $RG_CH03 \
    -p ${RG_CH03}-appsvcplan \
    -n ${RG_CH03}-disphostname \
    -i ${ACR}.azurecr.io/disp-hostname:0.0.1

az webapp config container set \
    -g $RG_CH03 \
    -n ${RG_CH03}-disphostname \
    --docker-custom-image-name ${ACR}.azurecr.io/disp-hostname:0.0.1 \
    --docker-registry-server-url ${ACR}.azurecr.io \
    --docker-registry-server-user $ACR \
    --docker-registry-server-password $PASS