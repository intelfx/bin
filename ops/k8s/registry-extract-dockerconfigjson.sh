#!/bin/bash

jq -r '.data[".dockerconfigjson"] | @base64d'
