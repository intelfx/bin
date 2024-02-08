#!/bin/bash

exec yq '.data |= map_values(@base64d)'
