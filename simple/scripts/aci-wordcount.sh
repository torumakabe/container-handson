#!/bin/bash

YOUR_PREFIX="YOUR PREFIX"

az container create \
    -g handson-container-aci-rg \
    -l westus2 \
    -n ${YOUR_PREFIX}-wordcount \
    --image microsoft/aci-wordcount:latest \
    --restart-policy OnFailure

az container show \
    -g handson-container-aci-rg \
    -l westus2 \
    -n ${YOUR_PREFIX}-wordcount \
    --query containers[0].instanceView.currentState.state

az container logs \
    -g handson-container-aci-rg \
    -l westus2 \
    -n ${YOUR_PREFIX}-wordcount
