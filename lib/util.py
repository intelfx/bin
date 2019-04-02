import os
import os.path as p
import sys
import subprocess
import tempfile
import logging
import yaml

# TODO: mutable container modifications are honored (attr-converted) only for dict itself
# i. e. `an_attrdict['newindex'] = { 'some': 'dict' }` will work, but
# `an_attrdict['newindex'].append({ 'some': 'dict' }` won't convert the new dict
class attrdict(dict):
	# attr-convert: recursively convert dict -> attrdict in all known containers
	@staticmethod
	def _convert(v):
		if isinstance(v, dict) and not isinstance(v, attrdict):
			return attrdict(v)
		if isinstance(v, list):
			return attrdict._list(v)
		if isinstance(v, set):
			return attrdict._set(v)
		return v


	# "attrlist" fake object: list, recursively attr-converted
	@staticmethod
	def _list(obj):
		return [ attrdict._convert(x) for x in obj ]


	# "attrset" fake object: set, recursively attr-converted
	@staticmethod
	def _set(obj):
		return { attrdict._convert(x) for x in obj }


	# "attrdict" object: dict, recursively attr-converted,
	# plus actual attr-property: attribute access translates to index access
	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)
		# Recursively convert dict -> attrdict
		for k, v in self.items():
			super().__setitem__(k, attrdict._convert(v))
		# Magic!
		self.__dict__ = self


	def __setitem__(self, k, v):
		super().__setitem__(k, attrdict._convert(v))


	def __setattr__(self, k, v):
		super().__setattr__(k, attrdict._convert(v))


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


def attrconvert(data):
	return attrdict._convert(data)


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
		level='LIB_DEBUG' in os.environ and logging.DEBUG or logging.INFO,
		format=fmt
	)


def file_get(path):
	with open(path, 'r') as f:
		return f.read()


def file_put(path, text):
	with open(path, 'w') as f:
		return f.write(text)
