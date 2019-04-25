#!/bin/bash

for i in {1..10};
do
    helm ls > /dev/null 2>&1
    if [ $? ]; then
        exit 0
    else
        sleep 5
    fi
done
echo "Error: Tiller verification failed."
exit 1