#!/bin/bash

NAMESPACE="default"  # Change to the namespace where your PVCs are located
LOCAL_DIR="./backup" # Change to the local directory where you want to store the backup

# Get a list of all PVCs in the namespace
PVCS=$(kubectl get pvc -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}')

for PVC in ${PVCS}; do
  # Create a temporary pod for each PVC
  POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: temp-pod-"${PVC}"
  namespace: "${NAMESPACE}"
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
      claimName: "${PVC}"
EOF
)

  echo "${POD_YAML}" | kubectl apply -f -

  echo "Waiting for pod temp-pod-${PVC} to be ready..."

  while [[ $(kubectl get pods temp-pod-"${PVC}" -n "${NAMESPACE}" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do 
    echo "waiting..." && sleep 5; 
  done

  # Restore data
  kubectl cp "${LOCAL_DIR}"/"${PVC}".tar.gz "${NAMESPACE}"/temp-pod-"${PVC}":/data.tar.gz
  kubectl exec -it temp-pod-"${PVC}" -n "${NAMESPACE}" -- apk add tar && kubectl exec -it temp-pod-"${PVC}" -n "${NAMESPACE}" -- tar -xzvf /data.tar.gz -C /data

  # Delete the temporary pod
  kubectl delete pod temp-pod-"${PVC}" -n "${NAMESPACE}"
done