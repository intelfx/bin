#!/bin/bash

exec jq '.data |= map_values(@base64d)'
