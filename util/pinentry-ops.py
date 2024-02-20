#!/usr/bin/python3


import logging
import re
import sys
import subprocess
import os

os.environ['LIB_DEBUG'] = '1'

import lib


PINENTRY_PATH = '/usr/bin/pinentry'

PINENTRY_OK = re.compile('OK(?: (.*))?\n')
PINENTRY_ERR = re.compile('ERR(?: (.*))?\n')
PINENTRY_D = re.compile('D (.*)\n')
PINENTRY_S = re.compile('S (.*)\n')


def pinentry_receive_one(p, forward=False):
	line = p.stdout.readline()
	match = PINENTRY_OK.fullmatch(line)
	if match:
		logging.debug(f'pinentry: OK ({match[1]})')
		return ('OK', match[1], line)

	match = PINENTRY_D.fullmatch(line)
	if match:
		logging.debug(f'pinentry: D ({match[1]})')
		return ('D', match[1], line)

	match = PINENTRY_S.fullmatch(line)
	if match:
		logging.debug(f'pinentry: S ({match[1]})')
		return ('S', match[1], line)

	match = PINENTRY_ERR.fullmatch(line)
	if match:
		if forward:
			logging.debug(f'pinentry: ERR ({match[1]})')
			return ('ERR', match[1], line)
		raise RuntimeError(f'pinentry: ERR ({match[1]})', ('ERR', match[1], line))

	raise RuntimeError(f'pinentry: unexpected ({line})', ('', '', line))


def pinentry_receive(p, forward=False):
	reply = dict()
	raw = list()
	while True:
		reply_type, reply_data, reply_raw = pinentry_receive_one(p, forward=forward)
		reply.setdefault(reply_type, []).append(reply_data)
		raw.append(reply_raw)
		if reply_type in ('OK', 'ERR'):
			return reply, raw


def pinentry_communicate(p, cmd):
	logging.debug(f'pinentry: sending {cmd}')
	p.stdin.write(f'{cmd}\n')
	p.stdin.flush()
	return pinentry_receive(p)


def pinentry_expect_ok(r):
	if 'OK' not in r:
		raise RuntimeError(f'pinentry: expected OK, got reply without one: {r}')
	if len(r) != 1:
		raise RuntimeError(f'pinentry: expected OK, got reply with extras: {r}')

def pinentry_forward(p, cmd):
	logging.debug(f'pinentry: forwarding {cmd.rstrip()}')
	p.stdin.write(cmd)
	p.stdin.flush()
	return pinentry_receive(p, forward=True)

def pinentry_readback(raw):
	for r in raw:
		sys.stdout.write(r)
	sys.stdout.flush()

with lib.Popen(
	[ PINENTRY_PATH ] + sys.argv[1:],
	stdin=subprocess.PIPE,
	stdout=subprocess.PIPE,
	stderr=sys.stderr,
) as pinentry:
	reply, raw = pinentry_receive(pinentry)
	pinentry_expect_ok(reply)
	pinentry_readback(raw)

	reply, raw = pinentry_communicate(pinentry, 'OPTION allow-external-password-cache')
	pinentry_expect_ok(reply)

	while True:
		cmd = sys.stdin.readline()
		if not cmd:
			break
		reply, raw = pinentry_forward(pinentry, cmd)
		pinentry_readback(raw)
