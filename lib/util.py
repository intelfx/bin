import os
import os.path as p
import sys
import subprocess
import tempfile
import logging
import yaml

class attrdict(dict):
	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)
		# Recursively convert dict -> attrdict
		for k, v in self.items():
			if isinstance(v, dict) and not isinstance(v, attrdict):
				super().__setitem__(k, attrdict(v))
		# Magic!
		self.__dict__ = self


	def __setitem__(self, k, v):
		if isinstance(v, dict) and not isinstance(v, attrdict):
			v = attrdict(v)
		super().__setitem__(k, v)


	def __setattr__(self, k, v):
		if isinstance(v, dict) and not isinstance(v, attrdict):
			v = attrdict(v)
		super().__setattr__(k, v)


	@staticmethod
	def from_yaml(loader, node):
		data = attrdict()
		yield data
		value = loader.construct_mapping(node)
		data.update(value)


	@staticmethod
	def to_yaml(dumper, data):
		return dumper.represent_mapping(u'!attrdict', data)


	@staticmethod
	def to_yaml_safe(dumper, data):
		return dumper.represent_dict(data)


yaml.add_constructor(u'!attrdict', attrdict.from_yaml)
for rep, fun in (
	(yaml.representer.SafeRepresenter, attrdict.to_yaml_safe),
	(yaml.representer.Representer, attrdict.to_yaml_safe)
):
	rep.add_representer(attrdict, fun)
	rep.add_multi_representer(attrdict, fun)


def run(args, **kwargs):
	return subprocess.run(
		args=args,
		check=True,
		universal_newlines=True,
		**kwargs,
	)


def Popen(args, **kwargs):
	return subprocess.Popen(
		args=args,
		universal_newlines=True,
		**kwargs,
	)


# HACK: bash does not honor ~/.profile when called from ssh.
# I have no idea why this is so, but let's source .profile by hand.
def _prepare_ssh_cmd(cmd):
	cmd[0] = '\n'.join([
		'[[ -e .profile ]] && source .profile',
		cmd[0]
	])
	return cmd


def mkopen(path, options):
	os.makedirs(p.dirname(path), exist_ok=True)
	return open(path, options)


def mkmount(*, src, dest, type=None, options=[], args=[]):
	args = [
		'mount',
		*args,
		src,
		dest
	]
	if type is not None:
		args += [ '-t', type ]
	if options:
		args += [ '-o', ','.join(options) ]

	os.makedirs(dest, exist_ok=True)
	return run(args)


def configure_logging(*, prefix=None):
	fmt=''
	if prefix is not None:
		fmt=f'{prefix}: '
	fmt+='%(levelname)s: %(message)s'

	logging.basicConfig(
		level=logging.INFO,
		format=fmt
	)

