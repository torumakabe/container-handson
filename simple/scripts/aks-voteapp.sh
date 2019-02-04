#!/bin/bash

YOUR_PREFIX="tomakabe07"

cat ../manifest/azure-vote-all-in-one-redis.yaml\
| sed -e "s/YOUR_PREFIX/${YOUR_PREFIX}/g"\
| kubectl apply -f -