#!/bin/bash

# Workaround: Verify number of CRDs (53) before Istio installation to avoid validation error https://github.com/istio/istio/issues/11551

for i in {1..10};
do
    CRD=$(kubectl get crds | grep 'istio.io\|certmanager.k8s.io' | wc -l)
    if [ $CRD = 53 ]; then
        exit 0
    else
        sleep 5
    fi
done
echo "Error: CRDs verification failed."
exit 1