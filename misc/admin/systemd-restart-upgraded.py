#!/usr/bin/env python3

#
# systemd-restart-upgraded.py -- a dumb script that will search for processes holding deleted files
#                                and restart systemd(1) units owning these processes.
#

import lib
import attr
import logging
import subprocess
import json
import sys
import os
import os.path as p
import re


def strip_newline(iterable):
	for line in iterable:
		if not line.endswith('\n'):
			raise RuntimeError(f'malformed_input: does not end with a newline: {line}')
		yield line[:-1]


@attr.s(kw_only=True)
class LsofLine:
	type: str = attr.ib()
	data: str = attr.ib()

	@classmethod
	def parse(cls, line):
		return cls(
			type=line[0],
			data=line[1:],
		)


@attr.s(kw_only=True)
class LsofRecord:
	type: str = attr.ib()
	pid: str = attr.ib(default=None)
	path: str = attr.ib()

	@classmethod
	def parse(cls, fields):
		fields_map = {
			'p': 'pid',
			'f': 'type',
			'n': 'path',
		}
		fields_trans = {
			'p': int,
		}
		kwargs = dict()

		for k, v in fields.items():
			if v.type in fields_map:
				kwargs[fields_map[v.type]] = fields_trans[v.type](v.data) if v.type in fields_trans else v.data
			else:
				raise ValueError(f'LsofRecord: unknown field: {v}')

		return cls(**kwargs)


def Lsof(args, **kwargs):
	with subprocess.Popen(
		args=args,
		stdin=subprocess.DEVNULL,
		stdout=subprocess.PIPE,
		text=True,
		**kwargs,
	) as lsof:
		fields = dict()

		def make_record():
			logging.debug(f'lsof: creating record from {fields}')
			record = LsofRecord.parse(fields)
			logging.debug(f'lsof: record: {record}')
			return record

		for line in strip_newline(lsof.stdout):
			line = LsofLine.parse(line)
			# emit a record on a process set or a file set boundary,
			# if the record is complete enough
			# (i. e. not before first process set and not before
			#  first file set in a process set)
			if line.type in {'p', 'f'} and {'p', 'f'}.issubset(fields.keys()):
				yield make_record()
			# clear all fields on a process set boundary, so that
			# the above check works
			if line.type == 'p':
				fields = dict()
			logging.debug(f'lsof: line: {line}')
			fields[line.type] = line

		# emit last record
		yield make_record()




class CustomJSONEncoder(json.JSONEncoder):
	def default(self, o):
			# accept custom iterables
			try:
				iterable = iter(o)
			except TypeError:
				pass
			else:
				return list(iterable)

			# accept everything str-able
			try:
				s = str(o)
			except:
				pass
			else:
				return s

			# Let the base class default method raise the TypeError
			return json.JSONEncoder.default(self, o)


@attr.s(kw_only=True)
class Process:
	pid: int = attr.ib()
	exe: str = attr.ib()
	cgroup: dict = attr.ib()
	files: set = attr.ib(factory=set)

	@classmethod
	def from_proc(cls, pid):
		proc = p.join('/proc', str(pid))
		return cls(
			pid=pid,
			exe=os.readlink(p.join(proc, 'exe')),
			cgroup={
				cg[1]: cg[2]
				for cg
				in [
					line.split(':', 2)
					for line
					in lib.file_get(p.join(proc, 'cgroup')).splitlines()
				]
			},
		)

	SYSTEM_UNIT_RE = re.compile('^/(([^/]+\.slice)/)*(?P<unit>[^/]+\.service)$')
	USER_UNIT_RE = re.compile('^/(([^/]+\.slice)/)*user@(?P<uid>[0-9]+)\.service/(([^/]+\.slice)/)*(?P<unit>[^/]+\.service)$')
	OTHER_UNIT_RE = re.compile('^/(([^/]+\.slice)/)*(?P<unit>[^/]+)$')

	def unit(self):
		# unified cgroups
		if '' in self.cgroup:
			cgroup = self.cgroup['']
		# legacy cgroups
		elif 'name=systemd' in self.cgroup:
			cgroup = self.cgroup['name=systemd']
		else:
			raise RuntimeError(f'Process: failed to parse cgroups of process {self.pid}: {self.cgroup}')

		m = Process.SYSTEM_UNIT_RE.match(cgroup)
		if m:
			return SystemUnit(unit=m['unit'])
		m = Process.USER_UNIT_RE.match(cgroup)
		if m:
			return UserUnit(uid=int(m['uid']), unit=m['unit'])
		m = Process.OTHER_UNIT_RE.match(cgroup)
		if m:
			return OtherUnit(cgroup=cgroup, unit=m['unit'])
		raise RuntimeError(f'Process: failed to parse systemd cgroup of process {self.pid}: {cgroup}')


@attr.s(kw_only=True, frozen=True)
class SystemUnit:
	unit: str = attr.ib()

	def __str__(self):
		return self.unit

	def systemctl(self):
		return [ 'systemctl', '--system' ]


@attr.s(kw_only=True, frozen=True)
class UserUnit:
	uid: int = attr.ib()
	unit: str = attr.ib()

	def __str__(self):
		return f'{self.unit} of user {self.uid}'

	def systemctl(self):
		return [
			'setpriv',
			'--reuid', f'{self.uid}',
			'--regid', f'{self.uid}', # FIXME this assumes GID==UID exists, find how to set GID to primary group in setpriv(1)
			'--init-groups',
			'env',
			f'XDG_RUNTIME_DIR=\'/run/user/{self.uid}\'',
			f'DBUS_SESSION_BUS_ADDRESS=\'unix:path=/run/user/{self.uid}/bus\'',
			'systemctl',
			'--user',
		]


@attr.s(kw_only=True, frozen=True)
class OtherUnit:
	cgroup: str = attr.ib()
	unit: str = attr.ib()

	def __str__(self):
		return f'{self.unit} in {self.cgroup}'

	def systemctl(self):
		return None


def calldefault(dict, key, callable):
	if key in dict:
		return dict[key]
	else:
		value = callable(key)
		dict[key] = value
		return value


def describe_unit(unit, processes, file):
	print(f'# {unit}', file=file)
	for p in processes:
		print(f'#   - {p.exe} (PID={p.pid})', file=file)
		for f in p.files:
			print(f'#      - {f}', file=file)

def emit_restart_group(name, command, group, file):
	if group:
		print(' ')
		print('#')
		print(f'# {name}')
		print('#')
		for k, v in group.items():
			describe_unit(unit=k, processes=v, file=file)
		if command:
			print(' '.join(command + [ u.unit for u in group.keys() ]))

def main():
	# list open deleted files and group them by holding process
	processes = dict()
	for r in Lsof([ 'lsof', '-F', 'pfn' ]):
		if r.type == 'DEL' and r.path.startswith('/usr'):
			p = processes.get(r.pid, None)
			if p is None:
				p = processes.setdefault(r.pid, Process.from_proc(r.pid))
			p.files.add(r.path)

	# group processes by units
	units = dict()
	for p in processes.values():
		units.setdefault(p.unit(), list()).append(p)

	# group units-processes by systemctl invocations
	systemctls = dict()
	ungrouped = dict()
	for unit, processes in units.items():
		s = unit.systemctl()
		if s is None:
			s = ungrouped
		else:
			s = systemctls.setdefault(tuple(s), dict())
		s[unit] = processes

	# write a shell script
	emit_restart_group(
		file=sys.stdout,
		name='Ungrouped units',
		command=[ 'echo' ],
		group=ungrouped,
	)
	for k, v in systemctls.items():
		emit_restart_group(
			file=sys.stdout,
			name=f'Units in {" ".join(k)}',
			command=list(k) + [ 'restart' ],
			group=v,
		)


if __name__ == '__main__':
	main()
