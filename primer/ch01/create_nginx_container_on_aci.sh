#!/bin/bash

az container create \
    -g $RG_CH01 \
    -n ${RG_CH01}-nginx \
    --image nginx \
    --ip-address public