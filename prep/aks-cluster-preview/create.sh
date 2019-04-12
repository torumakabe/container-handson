#!/bin/bash

az aks create \
  --resource-group your-aks-cluster-resource-group-name \
  --name your-aks-cluster-resource-group-name \
  --kubernetes-version 1.12.7 \
  --node-count 2 \
  --node-vm-size Standard_D2s_v3 \
  --enable-vmss \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 5 \
  --service-principal your-sp \
  --client-secret your-sp-secret \
  --enable-addons monitoring \
  --workspace-resource-id "your-workspace-resource-id"