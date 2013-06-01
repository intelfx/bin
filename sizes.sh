#!/bin/bash
du -hs --apparent-size -Ll * | sort -hk 1
