#!/bin/bash

set -e

NAMESPACE="alternative"  # Change to the namespace where your PVCs are located
LOCAL_DIR="./backup" # Change to the local directory where you want to store the backup

# get list of pvcs from the persistentvolumeclaim folder
PVCS=$(ls -l ./persistentvolumeclaim | awk '{print $9}')

# Remve the .yaml suffix from the list of pvcs
PVCS=$(echo $PVCS | tr " " "\n" | sed 's/.yaml//g')

for PVC in ${PVCS}; do
  (
    # LOGFILE="${LOCAL_DIR}/${PVC}_restore.log"
    # exec &> >(tee -a "${LOGFILE}")

    # Create a temporary pod for each PVC
    POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: temp-pod-${PVC}
  namespace: ${NAMESPACE}
spec:
  containers:
  - name: temp-pod
    image: alpine
    command: ["/bin/sh", "-c", "sleep 3600"]
    volumeMounts:
    - mountPath: "/data"
      name: volume
  restartPolicy: Never
  volumes:
  - name: volume
    persistentVolumeClaim:
      claimName: ${PVC}
EOF
)

    echo "${POD_YAML}" | kubectl apply -f -

    echo "Waiting for pod temp-pod-${PVC} to be ready..."

    while [[ $(kubectl get pods temp-pod-$PVC -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do 
      echo "waiting..." && sleep 5; 
    done

    kubectl cp "${LOCAL_DIR}"/"${PVC}".tar.gz "${NAMESPACE}"/temp-pod-"${PVC}":/data.tar.gz && echo "Copy successful" || echo "Copy failed"
    kubectl exec -it temp-pod-"${PVC}" -n "${NAMESPACE}" -- apk add tar && kubectl exec -it temp-pod-"${PVC}" -n "${NAMESPACE}" -- tar -xzvf /data.tar.gz -C /data && echo "Restore successful" || echo "Restore failed"

    # Delete the temporary pod
    kubectl delete pod temp-pod-"${PVC}" -n "${NAMESPACE}"
  ) &
done

# Wait for all background jobs to finish
wait
