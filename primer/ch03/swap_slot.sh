#!/bin/bash

az webapp deployment slot swap \
    -g $RG_CH03 \
    -n ${RG_CH03}-disphostname \
    --slot staging \
    --target-slot production