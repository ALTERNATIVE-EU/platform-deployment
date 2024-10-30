#!/bin/bash

# Get a list of all PVCs in the namespace only starting with "claim-"
for n in $(kubectl get pvc -n alternative -o jsonpath='{.items[*].metadata.name}' | tr " " "\n" | grep "^claim-")
do
    mkdir -p persistentvolumeclaim/
    kubectl get pvc "${n}" -n alternative -o yaml > persistentvolumeclaim/"${n}".yaml
done
