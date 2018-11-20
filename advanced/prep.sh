#!/bin/bash

PREFIX="PREFIX"
SP="${PREFIX}-aks-handson"
RG="${PREFIX}-aks-handson-rg"

az ad sp create-for-rbac -n $SP
az group create -n $RG -l japaneast