#!/bin/bash

RG="PREFIX-aks-handson-rg"
AKS_CLUSTER_NAME="PREFIX-aks-handson"
AZ_SP_CLIENT_ID="YOUR-AZ-SP-CLIENT-ID"
AZ_SP_CLIENT_SECRET="YOUR-AZ-SP-CLIENT-SECRET"

az group create -n $RG -l japaneast

az aks create \
    --resource-group $RG \
    --name $AKS_CLUSTER_NAME \
    --kubernetes-version 1.11.2 \
    --node-count 2 \
    --node-vm-size Standard_D2s_v3 \
    --service-principal $AZ_SP_CLIENT_ID \
    --client-secret $AZ_SP_CLIENT_SECRET

az aks get-credentials -g $RG -n $AKS_CLUSTER_NAME --admin