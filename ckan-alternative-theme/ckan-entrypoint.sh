#!/bin/bash
set -e

# Update CKAN configuration
ckan config-tool /srv/app/production.ini -f /srv/app/keycloak_auth-config
ckan config-tool /srv/app/production.ini -f /srv/app/cloudstorage-config
ckan config-tool /srv/app/production.ini -f /srv/app/custom-ckan-config

# Start CKAN
exec "$@"