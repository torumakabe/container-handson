#!/bin/bash

az container create \
    -g $RG_CH01 \
    -n ${RG_CH01}-wordcount \
    --image microsoft/aci-wordcount:latest \
    --restart-policy OnFailure

az container show \
    -g $RG_CH01 \
    -n ${RG_CH01}-wordcount \
    --query containers[0].instanceView.currentState.state

az container logs \
    -g $RG_CH01 \
    -n ${RG_CH01}-wordcount