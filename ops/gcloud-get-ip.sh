#!/bin/bash

gcloud compute instances describe "$@" --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
