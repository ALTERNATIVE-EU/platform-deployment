# This folder contains scripts to backup and restore jupyterlab PVCs

## Requirements

* kubectl

## Directory structure

* backup-data.sh - backup data from all jupyterlab PVCs
* backup-pvc.sh - backup manifests of all jupyterlab PVCs
* restore-data.sh - restore data to all jupyterlab PVCs
* restore-pvc.sh - restore manifests of all jupyterlab PVCs

## Backup

To backup all jupyterlab PVCs run:

```bash
./backup-data.sh
./backup-pvc.sh
```

## Restore

Edit each manifest in persistentvolumeclaim folder to match your environment and run:

```bash
./restore-pvc.sh
./restore-data.sh
```
