#!/usr/bin/env python3

import argparse
import json
import os
import sys
import base64
import urllib

parser = argparse.ArgumentParser()

parser.add_argument('-u', '--username', type=str, required=True)
parser_p = parser.add_mutually_exclusive_group(required=True)
parser_p.add_argument('-p', '--password', type=str)
parser_p.add_argument('--password-stdin', action='store_true')
parser.add_argument('hostname', type=str)

args = parser.parse_args()


def get_username(args):
	return args.username


def get_password(args):
	if args.password_stdin:
		return sys.stdin.read()
	else:
		return args.password

docker_config_json = {
	'auths': {
		args.hostname: {
			'auth': base64.b64encode(f'{args.username}:{get_password(args)}'.encode('ascii')).decode('ascii'),
		},
	},
}

json.dump(docker_config_json, sys.stdout)
