#!/bin/bash

cp -n -R -T /var/alternative-anaconda/init-home/jovyan /home/jovyan
conda config --set auto_activate_base false
jupyterhub-singleuser