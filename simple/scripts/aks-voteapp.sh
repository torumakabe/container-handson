#!/bin/bash

YOUR_PREFIX="YOUR PREFIX"

cat ../manifest/azure-vote-all-in-one-redis.yaml\
| sed -e "s/YOUR_PREFIX/${YOUR_PREFIX}/g"\
| kubectl apply -f -