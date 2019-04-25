#!/bin/bash

az group create -n $RG_RGST -l japaneast

az acr create \
    -g $RG_RGST \
    -n $ACR \
    --sku Standard \
    --admin-enabled true