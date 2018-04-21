#!/usr/bin/env python3

import re

from .util import *

OPKG_STATUS = '/usr/lib/opkg/status'

class Db:
	@staticmethod
	def _transform_value(k, v):
		if k == 'Conffiles':
			return v.split('\n ')[1:] # multiline-list value; drop leading separator
		elif k == 'Status':
			return v.split(' ') # flags
		elif k == 'Installed-Time':
			return int(v)
		elif k == 'Depends':
			return v.split(', ')
		else:
			return v


	@staticmethod
	def _parse(text):
		return [ {
				k: Db._transform_value(k, v)
				for k, v
				in [
					re.split(': |:(?=\n)', attr) # split into k/v (possibly multiline-list)
					for attr
					in re.split('\n(?=[^ ])', pkg) # split into lines (mind the continuations)
				]
			}
			for pkg
			in text.rstrip('\n').split('\n\n') # split into packages (drop trailing \n\n)
		]


	def __init__(self, opkg_status = OPKG_STATUS):
		self.db = Db._parse(open(opkg_status).read())
