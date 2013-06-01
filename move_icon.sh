#!/bin/bash
DIR=$(dirname $1)
mkdir -p backup/$DIR
mv $1 backup/$DIR
