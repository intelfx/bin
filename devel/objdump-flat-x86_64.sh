#!/bin/bash

objdump -Db binary -m i386 -M x86_64,intel,intel-mnemonic "$@"
