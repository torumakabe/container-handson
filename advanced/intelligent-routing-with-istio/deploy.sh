#!/bin/bash

kubectl apply -f namespace.yaml
kubectl apply -f kubernetes/step-1-create-voting-app.yaml --namespace voting