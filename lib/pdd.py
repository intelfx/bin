#!/usr/bin/env python3

import re
import socket
import yaml
import json
import requests

from .util import *

class Pdd:
	class Error(RuntimeError):
		pass

	def _api_method(self, name):
		return f'https://pddimp.yandex.ru/api2/admin/dns/{name}'

	def _api_get(self, method, args):
		return requests.get(
			url=self._api_method(method),
			headers=self.headers,
			params=args,
		)

	def _api_post(self, method, args):
		return requests.post(
			url=self._api_method(method),
			headers=self.headers,
			data=args,
		)

	def _api_wrap(self, fn, method, **kwargs):
		args = dict()
		args.update(self.args)
		args.update(kwargs)

		try:
			response = fn(method=method, args=args)
			response.raise_for_status()
			response = attrdict(response.json())
			if response.success == 'ok':
				return response
			elif response.success == 'error' and 'error' in response:
				raise RuntimeError(f'API error: {response.error}')
			else:
				raise RuntimeError(f'Invalid API response: {response}')
		except (requests.exceptions.RequestException, RuntimeError) as e:
			raise Pdd.Error(f'Pdd: {self.config.domain}: failed to \'{method}\': {str(e)}')


	def __init__(self, config):
		self.config = attrdict(config)
		self.args = {
			'domain': self.config.domain,
		}
		self.headers = {
			'PddToken': self.config.token,
		}
		self.domain = self.config.domain


	def list(self):
		response = self._api_wrap(
			fn=self._api_get,
			method='list',
		)
		return response.records


	def add(self, type, **kwargs):
		response = self._api_wrap(
			fn=self._api_post,
			method='add',
			type=type,
			**kwargs,
		)
		return response.record


	def edit(self, record_id, **kwargs):
		# may pass the whole record dict here
		if isinstance(record_id, dict):
			record_id = record_id['record_id']
		response = self._api_wrap(
			fn=self._api_post,
			method='edit',
			record_id=record_id,
			**kwargs,
		)
		return response.record

	def delete(self, record_id):
		# may pass the whole record dict here
		if isinstance(record_id, dict):
			record_id = record_id['record_id']
		response = self._api_wrap(
			fn=self._api_post,
			method='del',
			record_id=record_id,
		)

