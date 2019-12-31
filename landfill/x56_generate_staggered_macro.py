#!/usr/bin/env python3

import os
import sys
import enum
import itertools
import attr

t_tf = 1.20 + 0.025 # trigger to fire deplay (charge)
t_ft = 0.83 + 0.025 # fire to trigger delay (cooldown)

@attr.s(kw_only=True, eq=False, order=False)
class Action:
	class Type(enum.Enum):
		PrimaryTrigger = 1
		PrimaryRelease = 2
		SecondaryTrigger = 3
		SecondaryRelease = 4
		Dummy = 5


	type: Type = attr.ib()
	timestamp: float = attr.ib()

	def __eq__(this, rhs):
		return this.timestamp == rhs.timestamp

	def __lt__(this, rhs):
		return this.timestamp < rhs.timestamp


def generate_sequence(count: int, delay: float, trigger: Action.Type, release: Action.Type):
	ts = delay

	for i in range(count):
		yield Action(type=trigger, timestamp=ts)
		ts += t_tf
		yield Action(type=release, timestamp=ts)
		ts += t_ft
	yield Action(type=Action.Type.Dummy, timestamp=ts)


def generate_pr0(delay: float, action: Action):
	templates = {
		Action.Type.PrimaryTrigger:   '        [action device=mouse time=0x{time_ms:08X} usage=0x00000001 page=0x00000009 value=0x00000001]',
		Action.Type.SecondaryTrigger: '        [action device=mouse time=0x{time_ms:08X} usage=0x00000002 page=0x00000009 value=0x00000001]',
		Action.Type.PrimaryRelease:   '        [action device=mouse time=0x{time_ms:08X} usage=0x00000001 page=0x00000009]',
		Action.Type.SecondaryRelease: '        [action device=mouse time=0x{time_ms:08X} usage=0x00000002 page=0x00000009]',
		Action.Type.Dummy: ''
	}

	return templates[action.type].format(time_ms=round(delay*1000))


def main():
	count = 10
	seq_primary = generate_sequence(
		count,
		delay=0.0,
		trigger=Action.Type.PrimaryTrigger,
		release=Action.Type.PrimaryRelease,
	)
	seq_secondary = generate_sequence(
		count,
		delay=(t_tf+t_ft)/2,
		trigger=Action.Type.SecondaryTrigger,
		release=Action.Type.SecondaryRelease,
	)
	seq = sorted(itertools.chain(seq_primary, seq_secondary))

	print('      [actionblock')
	last_ts = 0
	for s in seq:
		ts = s.timestamp
		delay = s.timestamp - last_ts
		last_ts = s.timestamp
		pr0 = generate_pr0(delay=delay, action=s)
		if pr0:
			print(pr0)
	print('      ]')


if __name__ == '__main__':
	main()
