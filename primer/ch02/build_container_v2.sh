#!/bin/bash

az acr build \
    --registry $ACR \
     --image disp-hostname:0.0.2 \
     .