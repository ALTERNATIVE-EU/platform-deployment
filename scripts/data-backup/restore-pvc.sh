#!/bin/bash

for n in $(find persistentvolumeclaim -name '*.yaml')
do
    kubectl create -f "${n}"
done

