#!/bin/bash

YOUR_PREFIX="YOUR PREFIX"

az container create \
    -g handson-container-aci-rg \
    -l westus2 \
    -n ${YOUR_PREFIX}-nginx \
    --image nginx \
    --ip-address public