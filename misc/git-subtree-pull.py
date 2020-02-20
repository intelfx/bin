#!/usr/bin/env python3

import sys
import os
import os.path as p
import argparse
import subprocess

import attr
import yaml
import urllib.parse
import shlex


def run(args, *, stdredir=False, **kwargs):
	default_kwargs = {
		'check': True,
		'text': True,
	}
	default_kwargs.update(stdredir and {
		'stdin': sys.stdin,
		'stdout': sys.stdout,
		'stderr': sys.stderr,
	} or {
		'stdin': subprocess.DEVNULL,
		'stdout': subprocess.PIPE,
		'stderr': sys.stderr,
	})
	default_kwargs.update(kwargs)

	return subprocess.run(
		args,
		**default_kwargs,
	)


def parse_args(args=None):
	parser = argparse.ArgumentParser()
	parser.add_argument('yaml')
	parser.add_argument('-C', '--cache',
		default=p.join(
			run(['systemd-path', 'user-state-cache']).stdout.strip(),
			'git-subtree-pull',
		),
	)
	return parser.parse_args(args=args)


@attr.s(kw_only=True)
class Chart:
	local_prefix = attr.ib()
	repo = attr.ib()
	remote_prefix = attr.ib()

	@staticmethod
	def from_yaml(repos, **kwargs):
		kwargs['repo'] = repos[kwargs['repo']]
		return Chart(**kwargs)


@attr.s(kw_only=True)
class Repo:
	url = attr.ib()
	cache = attr.ib()

	@staticmethod
	def cache_path(url, args):
		url = urllib.parse.urlsplit(url)
		return p.join(
			args.cache,
			url.netloc,
			p.relpath(p.normpath(url.path), start='/'),
		)

	@staticmethod
	def from_url(url, args):
		return Repo(
			url=url,
			cache=Repo.cache_path(url, args),
		)


def parallel(script, input, nargs, jobs=None, **kwargs):
	return run(
		[
			'parallel',
			'--bar',
			f'-N{nargs}',
			f'-j{jobs or "100%"}',
			script,
		],
		stdredir=True,
		stdin=None,
		input='\n'.join(input),
		**kwargs,
	)


def main():
	args = parse_args()

	#
	# load yaml config
	#

	with open(args.yaml, 'r') as f:
		subtrees = yaml.safe_load(f)

	repos = {
		c['repo']: Repo.from_url(url=c['repo'], args=args)
		for c
		in subtrees['subtrees']
	}

	subtrees = [
		Chart.from_yaml(repos=repos, **c)
		for c
		in subtrees['subtrees']
	]

	toplevel = run([ 'git', 'rev-parse', '--show-toplevel' ], cwd=p.dirname(args.yaml) or '.').stdout.strip()

	#
	# fetch repos using parallel(1)
	#

	def fetch_input(repos):
		for r in repos.values():
			yield r.url
			yield r.cache

	fetch_script = '''
set -e
url={1}
cache={2}
if test -e "$cache"; then
	cd "$cache"
	git remote set-url origin "$url"
	git pull
else
	mkdir -p "${cache##*/}"
	git clone "$url" "$cache"
fi
'''.strip()

	parallel(
		script=fetch_script,
		input=fetch_input(repos),
		nargs=2,
	)


	#
	# subtree-split subtrees using parallel
	#

	def split_input(subtrees):
		for c in subtrees:
			yield c.repo.cache
			yield c.remote_prefix
			yield p.join('subtree', c.remote_prefix) if c.remote_prefix else 'subtree'

	split_script = '''
set -e
cache={1}
prefix={2}
branch={3}
cd "$cache"
git branch -D "$branch" || true
if test -z "$prefix"; then
	git branch -f "$branch"
else
	git subtree split -P "$prefix" -b "$branch"
fi
'''

	parallel(
		script=split_script,
		input=split_input(subtrees),
		nargs=3,
	)

	#
	# subtree-pull subtrees using parallel
	#

	def pull_input(subtrees):
		for c in subtrees:
			yield c.repo.cache
			yield p.join('subtree', c.remote_prefix) if c.remote_prefix else 'subtree'
			yield c.local_prefix

	pull_script = '''
set -e
cache={1}
branch={2}
prefix={3}
if test -d "$prefix"; then
	verb=pull
else
	verb=add
fi
if ! git subtree "$verb" --prefix "$prefix" "$cache" "$branch"; then
	git merge --abort || true
	echo "Merge failed:"
	echo "  git subtree $verb --prefix '$prefix' '$cache' '$branch'"
fi
'''

	parallel(
		script=pull_script,
		input=pull_input(subtrees),
		nargs=3,
		jobs=1,
		cwd=toplevel,
	)


if __name__ == '__main__':
	main()
