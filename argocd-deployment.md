# ALTERNATIVE Platform Installation and Management Guide

## Initial Setup

### 1. Create and Configure Namespace
```bash
# Create namespace
kubectl create ns alternative

# Create registry secret
kubectl create secret -n alternative docker-registry ionos-registry-secret \
  --docker-username=pull \
  --docker-password=<pass> \
  --docker-server=alternative.cr.de-fra.ionos.com

# Configure image pull secrets
kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "ionos-registry-secret"}]}'

```

### 2. Install ArgoCD
```bash
# Create ArgoCD namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Install ArgoCD CLI
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

# Get initial password
argocd admin initial-password -n argocd

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### 3. Deploy Components
```bash
# Install ingress controller and cert-manager
kubectl apply -f deployment/develop/applications/ingress-controller.yaml
kubectl apply -f deployment/develop/applications/cert-manager.yaml

# !Replace the placeholders
# Install Keycloak
kubectl apply -f deployment/develop/applications/keycloak.yaml

# Install Istio components
kubectl apply -f deployment/develop/applications/istio.yaml
kubectl apply -f deployment/develop/applications/istiod.yaml
```

## Keycloak Configuration

### 1. Initial Setup
```bash
# Get admin credentials (username is 'user')
kubectl get secret -n alternative keycloak -o jsonpath='{.data.admin-password}'|base64 --decode
```

### 2. Configuration Steps
1. Create alternative realm from `deployment/charts/keycloak/realms/alternative-realm.json`
2. Update URL parameters in `ckan-backend`, `ckan-frontend` and `jupyterhub` clients
3. Generate new client credentials for `ckan-backend` and `jupyterhub` clients
4. Configure realm email settings
5. Enable "Forgot password" functionality

## Database Setup

### Create Revoked Tokens Table
```bash
POSTGRES_PASSWORD=$(kubectl get secret --namespace alternative postgrescredentials -o jsonpath="{.data.postgresql-password}" | base64 -d)

kubectl run alternative-postgresql-client --rm --tty -i --restart='Never' \
  --namespace alternative \
  --image=docker.io/bitnami/postgresql:16.2.0-debian-11-r1 \
  --env="PGPASSWORD=$POSTGRES_PASSWORD" \
  --command -- psql --host postgres-0 -U postgres -d postgres -p 5432 \
  -c "CREATE TABLE revoked_tokens (jti TEXT PRIMARY KEY, revoked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP);"
```

## AI/ML API Configuration

```bash
# !Change the valueFiles path
# Install ingress controller and cert-manager
kubectl apply -f deployment/develop/applications/ai-ml-api.yaml
```

Install auth envoy filter by following the instructions https://github.com/ALTERNATIVE-EU/auth-envoy-filter. Skip step 6 (sidecar container).

### Configure Sidecar Container
```bash
# Enable sidecar injection
kubectl patch deployment $AI_ML_DEPLOYMENT -n $AI_ML_NAMESPACE \
--patch='{"spec": {"template": {"metadata": {"labels": {"sidecar.istio.io/inject": "true"}}}}}'

# Set CPU limit
kubectl patch deployment $AI_ML_DEPLOYMENT -n $AI_ML_NAMESPACE \
--patch='{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/proxyCPULimit": "0"}}}}}'

# Configure volume
kubectl patch deployment $AI_ML_DEPLOYMENT -n $AI_ML_NAMESPACE \
-p='{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/userVolume": "[{\"name\": \"jwt-revocation-validation\", \"persistentVolumeClaim\": {\"claimName\": \"jwt-revocation-validation\"}}]"}}}}}'

# Configure volume mount
kubectl patch deployment $AI_ML_DEPLOYMENT -n $AI_ML_NAMESPACE \
-p='{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/userVolumeMount": "[{\"mountPath\": \"/etc/istio/jwt-revocation-validation\", \"name\": \"jwt-revocation-validation\"}]"}}}}}'
```

## Platform Components Installation

### 1. Install CKAN
```bash
# !Change the valueFiles path
# !Replace the placeholders
kubectl apply -f deployment/develop/applications/ckan.yaml
```

### 2. Install Additional Components
```bash
kubectl apply -f deployment/develop/applications/alternative-manifests.yaml
kubectl apply -f deployment/develop/applications/jupyterhub-nfs.yaml
# !Change the valueFiles path
# !Replace the placeholders
kubectl apply -f deployment/develop/applications/jupyterhub.yaml
```

### 3. Configure Backup Jobs
1. Update configurations in:
   - `deployment/manifests/backup_job.yaml`
   - `deployment/manifests/backup_credentials.yaml`

2. Apply configurations:
```bash
kubectl apply -f ./deployment/manifests/backup_credentials.yaml
kubectl apply -f ./deployment/manifests/backup_job.yaml
```

## Backup Procedures

### 1. User Data Backup

#### PVC and User Data
```bash
# Backup PVCs
./backup-pvc.sh

# Backup user data
./backup-data.sh
```

### 2. Database Backups

#### CKAN and AI/ML API PostgreSQL
```bash
# Get PostgreSQL password
PGPASSWORD=$(kubectl get secret postgres -n alternative -o jsonpath="{.data.postgres-password}" | base64 --decode)

# Create backup
kubectl run -n alternative postgres-backup-pod -i --tty --restart='Never' \
  --env PGPASSWORD=$PGPASSWORD \
  --image=docker.io/bitnami/postgresql:16.1.0-debian-11-r5 -- bash -c "\
    pg_dumpall -h postgres -p 5432 -U postgres -f /tmp/ckan-all_databases.sql && \
    echo 'Backup of all databases successful' && sleep 3600"

# Copy backup locally
kubectl cp alternative/postgres-backup-pod:/tmp/ckan-all_databases.sql ./backup/ckan-all_databases.sql
```

#### Keycloak PostgreSQL
```bash
# Get Keycloak PostgreSQL password
KEYCLOAK_PASSWORD=$(kubectl get secret -n alternative keycloak-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode)

# Create backup
kubectl run -n alternative keycloak-postgres-backup-pod --rm -i --tty --restart='Never' \
  --env PGPASSWORD=$KEYCLOAK_PASSWORD \
  --image=docker.io/bitnami/postgresql:14.2.0-debian-10-r70 -- bash -c "\
    pg_dumpall -h keycloak-postgresql -p 5432 -U postgres -f /tmp/keycloak-all_databases.sql && \
    echo 'Keycloak backup successful' && sleep 3600"

# Copy backup locally
kubectl cp alternative/keycloak-postgres-backup-pod:/tmp/keycloak-all_databases.sql ./backup/keycloak-all_databases.sql
```

### 3. Solr Backup
```bash
# Create Solr backup
kubectl run -n alternative solr-backup-pod1 --rm -i --tty --restart='Never' \
  --image=alpine:3.15 -- sh -c "\
    apk add --no-cache curl && \
    curl -u 'admin:pass' -H 'Content-type:application/json' \
    'http://solr:8983/solr/admin/collections?action=BACKUP&collection=ckancollection&name=solr.dump&location=/opt/bitnami/solr/server/solr' && \
    echo 'Solr backup successful' && sleep 3600"

# Create archive
kubectl exec -it solr-0 -- sh -c "tar -czvf /tmp/solr-application-backup.tar.gz /opt/bitnami/solr/server/solr/solr.dump"

# Copy backup locally
kubectl cp alternative/solr-0:/tmp/solr-application-backup.tar.gz ./backup/solr-application-backup.tar.gz
```

### 4. Zookeeper Backup
```bash
# Create backup
kubectl exec -n alternative ckan-zookeeper-0 -- tar -pczvf /tmp/zookeeper-application-backup.tar.gz /bitnami

# Copy backup locally
kubectl cp alternative/ckan-zookeeper-0:/tmp/zookeeper-application-backup.tar.gz ./backup/zookeeper-application-backup.tar.gz
```

## Restore Procedures

### 1. User Data Restore

#### PVC and User Data
Before running restore scripts, update each file in `backup/persistentvolumeclaim/claim-*` with:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: claim-<user>
  namespace: alternative
  labels:
    app: jupyterhub
    component: singleuser-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: ionos-enterprise-hdd
```

Then run:
```bash
./restore-pvc.sh
./restore-data.sh
```

#### NFS Restore
```bash
# Copy backup to pod
kubectl cp ./backup/nfs-backup.tar <pod-name>:/tmp/nfs-backup.tar

# Extract backup
kubectl exec <pod-name> -- tar xvf /tmp/nfs-backup.tar -C /home/shared
```

### 2. Database Restores

#### Keycloak PostgreSQL
```bash
# Copy backup to pod
kubectl cp ./backup/keycloak-all_databases.sql keycloak-postgresql-0:/tmp/keycloak-all_databases.sql -n alternative

# Scale down Keycloak
kubectl scale -n alternative statefulsets keycloak --replicas=0

# Get PostgreSQL password
kubectl get secret -n alternative keycloak-postgresql -o jsonpath='{.data.password}' | base64 --decode

# Access PostgreSQL pod
kubectl exec -it -n alternative keycloak-postgresql-0 -- /bin/bash

# Set environment variables
export PGDATABASE=bitnami_keycloak
export PGUSER=bn_keycloak
export PGPASSWORD=$POSTGRES_PASSWORD

# Restore database
dropdb -f $PGDATABASE
createdb $PGDATABASE
psql -U $PGUSER -d $PGDATABASE -f /tmp/keycloak-all_databases.sql

# Delete PostgreSQL pod
kubectl -n alternative delete pod keycloak-postgresql-0

# Scale up Keycloak
kubectl -n alternative scale statefulsets keycloak --replicas=1

# Get new admin password
kubectl -n alternative get secret keycloak -o jsonpath='{.data.admin-password}' | base64 --decode
```

#### CKAN PostgreSQL
```bash
# Scale down CKAN
kubectl scale -n alternative deployment ckan --replicas=0

# Copy backup to pod
kubectl cp ./backup/ckan-all_databases.sql postgres-0:/tmp/ckan-all_databases.sql -n alternative

# Get PostgreSQL password
PGPASSWORD=$(kubectl get secret postgrescredentials -n alternative -o jsonpath="{.data.postgresql-postgres-password}" | base64 --decode)

# Access PostgreSQL pod
kubectl exec -it -n alternative postgres-0 -- /bin/bash

# Set environment variables
export PGDATABASE=ckan_default
export PGUSER=postgres
export PGPASSWORD=$PGPASSWORD

# Restore database
dropdb $PGDATABASE
createdb $PGDATABASE
psql -U $PGUSER -d $PGDATABASE -f /tmp/ckan-all_databases.sql

# Scale up CKAN
kubectl scale -n alternative deployment ckan --replicas=1
```

### 3. Zookeeper Restore
```bash
# Copy backup to pod
kubectl cp ./backup/zookeeper-application-backup.tar.gz ckan-zookeeper-0:/tmp/zookeeper-application-backup.tar.gz -n alternative

# Restore backup
kubectl exec -it ckan-zookeeper-0 -n alternative -- bash -c "\
  tar -xvf /tmp/zookeeper-application-backup.tar.gz -C /tmp && \
  rm /data/logs/* && \
  mv /tmp/bitnami/zookeeper/data/version-2/log.* /data/log/version-2/ && \
  rm /data/version-2/* && \
  mv /tmp/bitnami/zookeeper/data/version-2/* /data/version-2/"

# Restart pod
kubectl delete pod ckan-zookeeper-0 -n alternative
```

### 4. Solr Restore
```bash
# Copy backup to pod
kubectl cp ./backup/solr-application-backup.tar.gz solr-0:/opt/solr/server/home -n alternative

# Delete collection
curl "http://solr-svc.alternative.svc.cluster.local:8983/solr/admin/collections?action=DELETE&name=ckancollection"

# Create collection
curl "http://solr-svc.alternative.svc.cluster.local:8983/solr/admin/collections?action=CREATE&name=ckancollection&numShards=1&replicationFactor=1&collection.configName=ckanConfigSet"

# Restore collection
curl "http://solr-svc.alternative.svc.cluster.local:8983/solr/admin/collections?action=RESTORE&collection=ckancollection&name=solr.dump/ckancollection&location=/opt/solr/server/home"

# Restart Solr pod
kubectl delete pod solr-0 -n alternative

# Apply Solr init configuration
kubectl apply -f solr-init.yaml -n alternative
```

## Important Notes

## User Management

### Create Users
1. Add users in Keycloak
2. Add sysadmin users to the `admins` group

### Configure CKAN Settings
1. Access sysadmin settings
2. Update logo: `../ckanext-alternative_theme/ckanext/alternative_theme/public/images/fulllogo_transparent.png`
3. Configure additional settings as needed