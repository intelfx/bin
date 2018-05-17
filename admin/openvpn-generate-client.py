#!/usr/bin/env python3

import lib

import subprocess
import logging
import argparse
import re
import sys
import os.path as p


#
# main
#

parser = argparse.ArgumentParser()
parser.add_argument('--server-config', required=True,
	help='OpenVPN server configuration file'
)
parser.add_argument('--server-host', required=True, action='append',
	help='OpenVPN server address (may be specified more than once)'
)
parser.add_argument('--client-key',
	help='Path to client private key'
)
key_op = parser.add_mutually_exclusive_group()
key_op.add_argument('--client-key-decrypt', action='store_true',
	help='Decrypt client private key'
)
key_op.add_argument('--client-key-encrypt', action='store_true',
	help='(Re-)encrypt client private key with `openssl rsa` for compatibility'
)
parser.add_argument('--client-cert',
	help='Path to client certificate'
)
parser.add_argument('--pki',
	help='Path to the easy-rsa PKI'
)
parser.add_argument('--pki-client',
	help='Client name in the easy-rsa PKI'
)
parser.add_argument('-o', '--output', type=argparse.FileType('w'), default=sys.stdout,
	help='Generated OpenVPN client configuration file (stdout if not specified)'
)
args = parser.parse_args()

server_config_dir = p.dirname(args.server_config)

def nop(*args):
	pass

def out(line):
	print(line, file=args.output)

def handle_copy(*args):
	out(' '.join(args))

def handle_proto(key, value):
	re_proto = {
		'udp': 'udp',
		'tcp-server': 'tcp-client',
	}
	out(f'proto {re_proto[value]}')

# f is a file object
def inline_stream(key, f):
	out(f'<{key}>')
	text = f.read()
	if text[-1] != '\n':
		text += '\n'
	args.output.write(text)
	out(f'</{key}>')

# filename is taken verbatim
def inline_file(key, filename):
	return inline_stream(key, open(filename, 'r'))

# filename is taken relative to server config
def handle_inline_file(key, filename):
	return inline_file(key, p.join(server_config_dir, filename))

def handle_tls_auth(key, value):
	filename, direction = value.split(sep=None, maxsplit=1)
	re_direction = {
		'0': '1'
	}
	out(f'key-direction {re_direction[direction]}')
	handle_inline_file(key, filename)


options = {
	'proto': handle_proto,
	'port': handle_copy,
	'dev': handle_copy,
	'cipher': handle_copy,
	'auth': handle_copy,
	'compress': lambda *args: out('compress'),
	'comp-lzo': lambda *args: out('comp-lzo no'),
	'ca': handle_inline_file,
	'tls-auth': handle_tls_auth,
}

# server hostname
for server in args.server_host:
	out(f'remote {server}')

# TLS client
out(f'tls-client')

# server options
comment = re.compile(' *(#.*)?\n')
for line in [
	comment.sub('', line)
	for line
	in open(args.server_config, 'r')
	if not comment.fullmatch(line)
]:
	line_split = line.split(sep=None, maxsplit=1)
	key = line_split[0]
	if key == '':
		raise RuntimeError('Failed to parse server config: {line}')

	if key in options:
		logging.debug(f'Server config option: {line}')
		options[key](*line_split)
	else:
		logging.warning(f'Unhandled server config option: {line}')

if args.pki is not None or args.pki_client is not None:
	if args.client_key is not None or args.client_cert is not None:
		raise RuntimeError('Exactly one of (--pki, --pki-client) or (--client-key, --client-cert) must be specified')
	if args.pki is None or args.pki_client is None:
		raise RuntimeError('Both --pki and --pki-client must be specified')
	args.client_key = f'{args.pki}/pki/private/{args.pki_client}.key'
	args.client_cert = f'{args.pki}/pki/issued/{args.pki_client}.crt'

if args.client_key is not None or args.client_cert is not None:
	if args.client_key is None or args.client_cert is None:
		raise RuntimeError('Both --client-key and --client-cert must be specified')

# user certificate
inline_file('cert', args.client_cert)

# user private key
key_stream = open(args.client_key, 'r')

decode = None
# decrypt key if asked
if args.client_key_decrypt:
	decode = [ 'openssl', 'rsa' ]
# (re-)encrypt in PKCS#1 for compatibility (input from easy-rsa is usually PKCS#8)
elif args.client_key_encrypt:
	decode = [ 'openssl', 'rsa', '-aes256' ]
if decode is not None:
	decode = lib.Popen(
		decode,
		stdin=key_stream,
		stdout=subprocess.PIPE,
	)
	key_stream = decode.stdout

inline_stream('key', key_stream)
