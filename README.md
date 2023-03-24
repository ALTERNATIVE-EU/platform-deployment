# Install ALTERNATIVE CKAN Environment on K8S

## Requirements

You will need a cluster with:
- Ingress controller configured
- Cert-Manager configured
- Domain name resolving to ingress-controller's service external IP
- GCP bucket and credentials json file for that project
- Kubeconfig file for interaction with the cluster (set environment variable `KUBECONFIG` to point to it)

You also need to clone this repository and all the CKAN extension ones.

## Create Certificate

1. Update `dnsNames` and `issuerRef` params in `deployment/manifest/certificate.yaml`
2. Create the certificate resource
```
kubectl apply -f ./deployment/manifests/certificate.yaml
```

## Create Ingress

1. Update `tls` and `rules` params in `deployment/manifest/ingress.yaml`
2. Create the ingress resource
```
kubectl apply -f ./deployment/manifests/ingress.yaml
```

## Install Keycloak

1. Install helm chart
```
helm install -f ./deployment/charts/keycloak/values.yaml keycloak ./deployment/charts/keycloak/ --namespace default
```
2. Get admin credentials (username is `user`)
```
kubectl get secret keycloak -o jsonpath='{.data.admin-password}'|base64 --decode
```
3. Create alternative realm from json file `deployment/charts/keycloak/realms/alternative-realm.json`
4. Update URL parameters in `ckan-backend`, `ckan-frontend` and `jupyterhub` clients (add jupyterhub URL)
5. Generate new client credentials secret for `ckan-backend` and `jupyterhub` clients
6. Configure realm email settings
7. Enable `Forgot password` functionality

## Build ALTERNATIVE CKAN Docker Image

1. Update credentials in `ckan-alternative-theme/alternative-gcp-credentials.json`
2. Update configs in `ckan-alternative-theme/keycloak_auth-config` and `ckan-alternative-theme/cloudstorage-config`
3. Copy the CKAN extensions into `ckan-alternative-theme`
4. Build the image
```
docker build -f ./ckan-alternative-theme/AlternativeCKAN ./ckan-alternative-theme -t gcr.io/alternative-363010/ckan-alternative
```
5. Upload the image to the registry
```
docker push gcr.io/alternative-363010/ckan-alternative
```

## Install CKAN

1. Add chart repo
```
helm repo add keitaro-charts https://keitaro-charts.storage.googleapis.com
```
2. Update `deployment/manifests/ckan_values.yaml`
3. Install helm chart
```
helm install -f ./deployment/manifests/ckan_values.yaml ckan keitaro-charts/ckan
```
4. Wait for the ckan pod to become ready

## Create Users

Add users in Keycloak, sysadmin users should be in the group `admins`

## Change Settings

From sysadmin settings, change the logo with `../ckanext-alternative_theme/ckanext/alternative_theme/public/images/fulllogo_transparent.png` and update the rest of the options as you wish

## Install Jupyterhub

### Create Certificate

1. Update `dnsNames` and `issuerRef` params in `jupyterhub/manifests/certificate.yaml`
2. Create the certificate resource
```
kubectl apply -f ./jupyterhub/manifests/certificate.yaml
```

### Create Ingress

1. Update `tls` and `rules` params in `jupyterhub/manifests/ingress.yaml`
2. Create the ingress resource
```
kubectl apply -f ./jupyterhub/manifests/ingress.yaml
```

### Create Bucket Volume

1. Update `bucketName` and `pathToGCPCredsJsonFile`
2. Create volume resources
```
kubectl apply -k "github.com/ofek/csi-gcs/deploy/overlays/stable?ref=v0.9.0"
kubectl create secret generic csi-gcs-secret --from-literal=bucket=bucketName --from-file=key=pathToGCPCredsJsonFile
kubectl apply -f ./jupyterhub/manifests/pvc.yaml
kubectl apply -f ./jupyterhub/manifests/pv.yaml
```

### Build Custom Image

1. Build a new docker image
```
DOCKER_BUILDKIT=1 docker build -f ./jupyterhub/singleuser/Dockerfile ./jupyterhub/singleuser/ -t gcr.io/alternative-363010/alternative-singleuser
```
2. Push the new image
```
docker push gcr.io/alternative-363010/alternative-singleuser
```

### Install Helm Chart

1. Update the parameters in `jupyterhub/config.yaml`
2. Install helm chart
```
helm install -f ./jupyterhub/config.yaml alternative-jupyterhub ./jupyterhub/chart/ --version=2.0.0
```

## Backup Jobs

1. Update `deployment/manifests/postgres_backup.yaml` and `deployment/manifests/backup_credentials.yaml`
2. Apply the files
```
kubectl apply -f ./deployment/manifests/backup_credentials.yaml
kubectl apply -f ./deployment/manifests/postgres_backup.yaml
```