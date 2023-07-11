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

### Restore Keycloak Backup

1. Install the helm chart and wait for the pods to be ready and running
```
helm install -f ./deployment/charts/keycloak/values.yaml keycloak ./deployment/charts/keycloak/ --namespace default
```

2. Copy the `.dump` file to the Keycloak DB pod
```
kubectl cp keycloak.dump keycloak-postgresql-0:/tmp/backup.dump
```

3. Remove Keycloak pod
```
kubectl scale statefulsets keycloak --replicas=0
```

4. Get PostgreSQL password
```
kubectl get secret keycloak-postgresql -o jsonpath='{.data.password}' | base64 --decode
```

5. Enter Keycloak DB pod
```
kubectl exec -it keycloak-postgresql-0 /bin/bash
```

6. Set environment variables (replace `pass` with the PostgreSQL password)
```
export PGDATABASE=bitnami_keycloak
export PGUSER=bn_keycloak
export PGPASSWORD=pass
```

7. Recreate the DB from the backup file
```
dropdb -f $PGDATABASE
createdb $PGDATABASE
pg_restore -d $PGDATABASE /tmp/backup.dump
```

8. Restoring from the backup recreates the main user of Keycloak so the password in the secret will no longer be correct, to fix that:
- Start PostgreSQL console with `psql`
- Get the user ID of user with username `user`
```
select id from user_entity where "username"='user';
```
- Run these queries (replace `usr_id`)
```
delete from credential where "user_id"='usr_id';
delete from user_role_mapping where "user_id"='usr_id';
delete from user_entity where "id"='usr_id';
```
- Exit DB pod, delete it with the below command and wait for it to be recreated, ready and running again
```
kubectl delete pod keycloak-postgresql-0
```

9. Recreate Keycloak pod
```
kubectl scale statefulsets keycloak --replicas=1
```

10. Enter Keycloak with username `user` and password from this command `kubectl get secret keycloak -o jsonpath='{.data.admin-password}' | base64 --decode` and check if everything got recovered

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

## Restore CKAN PostgreSQL Backup

1. Copy the `.dump` file to the DB pod
```
kubectl cp postgres.dump postgres-0:/tmp/backup.dump
```

2. Get PostgreSQL password
```
kubectl get secret postgrescredentials -o jsonpath='{.data.postgresql-password}' | base64 --decode
```

3. Enter DB pod
```
kubectl exec -it postgres-0 /bin/bash
```

4. Set environment variables (replace `pass` with the PostgreSQL password)
```
export PGDATABASE=ckan_default
export PGUSER=postgres
export PGPASSWORD=pass
```

5. Restore the DB from the backup file
```
pg_restore -d $PGDATABASE /tmp/backup.dump --clean --if-exists
```

6. Exit the DB pod with `exit` and enter the CKAN pod (replace `ckan-pod` with the actual pod name)
```
kubectl exec -it ckan-pod /bin/bash
```

7. Rebuild the search index for datasets to be listed correctly
```
ckan -c production.ini search-index rebuild
```

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

### Create Shared Jupyter Volume

1. Create NFS required pvc resource
```
kubectl apply -f ./jupyterhub/manifests/nfs/pvc.yaml
```
2. Create NFS resources
```
kubectl apply -f ./jupyterhub/manifests/nfs/deployment.yaml
kubectl apply -f ./jupyterhub/manifests/nfs/service.yaml
```
3. Create Persistent volume required for shared PVC
```
kubectl apply -f ./jupyterhub/manifests/nfs/pv.yaml
```
4. Create shared PVC
```
kubectl apply -f ./jupyterhub/manifests/pvc.yaml
```

### Build Custom Image

1. Build a new docker image
```
DOCKER_BUILDKIT=1 docker build -f ./jupyterhub/singleuser/Dockerfile ./jupyterhub/singleuser/ -t alternative.cr.de-fra.ionos.com/alternative-singleuser:v0.0.7
```
2. Push the new image
```
docker push alternative.cr.de-fra.ionos.com/alternative-singleuser:v0.0.7
```

### Install Helm Chart

1. Update the parameters in `jupyterhub/config.yaml`
2. Install helm chart
```
helm install -f ./jupyterhub/config.yaml alternative-jupyterhub ./jupyterhub/chart/ --version=2.0.0
```

## Backup Jobs

1. Update the configurations in `deployment/manifests/backup_job.yaml` and `deployment/manifests/backup_credentials.yaml`
2. Apply the files
```
kubectl apply -f ./deployment/manifests/backup_credentials.yaml
kubectl apply -f ./deployment/manifests/backup_job.yaml
```