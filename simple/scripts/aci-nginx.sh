#!/bin/bash

YOUR_PREFIX="YOUR PREFIX"

az container create \
    -g handson-container-aci-rg \
    -n ${YOUR_PREFIX}-nginx \
    --image nginx \
    --ip-address public