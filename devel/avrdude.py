#!/usr/bin/python

import os
import sys
import argparse
import subprocess

class Operation:
	counter = 0

	def __init__(self, arg):
		# Default values for operation parameters.
		# avrdude accepts several short forms of the `-U` argument value,
		# so let's parse the value string incrementally.
		self.memtype = "flash"
		self.operation = "w"
		self.format = "a"

		try:
			# If this fails, we have the first short form:
			# -U filename => -U flash:w:filename:a
			self.memtype, self.operation, arg = arg.split(':', maxsplit=2)
			# If this fails, we have the second short form:
			# -U memtype:op:filename => -U memtype:op:filename:a
			self.path, self.format = arg.rsplit(':', maxsplit=1)
		except:
			self.path = arg

		if ((self.is_input() and (self.format == "m" or self.path == "/dev/stdin")) or
		    (self.is_output() and self.path in ("/dev/stdout", "/dev/stderr"))):
			# If we are writing an immediate value, or writing into
			# stdin, or reading into stdout/stderr, do not translate
			# anything.
			self.remote_path = self.path
			self.translate = False

		else:
			# Generate a unique enough file name to use on the remote side
			self.remote_path = f"{self.operation}-{self.memtype}-{Operation.counter}-{self.format}"
			Operation.counter += 1
			self.translate = True

	def __str__(self):
		return self.local()

	def local(self):
		return f"{self.memtype}:{self.operation}:{self.path}:{self.format}"

	def remote(self):
		return f"{self.memtype}:{self.operation}:{self.remote_path}:{self.format}"

	def need_copy(self):
		return self.translate

	def is_input(self):
		return self.operation in ("w", "v")

	def is_output(self):
		return self.operation in ("r")


parser = argparse.ArgumentParser(description='A wrapper around avrdude on a remote SSH-controlled host.')
parser.add_argument('hostname', metavar='HOSTNAME', help='hostname to SSH into')
parser.add_argument('-U', dest='ops', metavar='OPERATION', type=Operation, action='append', help='memory operation to translate to the remote avrdude')
args, remainder = parser.parse_known_args()

if args.ops is None:
	args.ops = []

print(f"hostname: {args.hostname}")
print(f"operations: {[str(o) for o in args.ops]}")
print(f"args: {remainder}")

# We need to copy all specified operation inputs to the remote, execute avrdude
# there and finally copy all specified operation outputs from the remote.
# We'd like to reuse a single SSH connection for all these operations,
# while still allowing avrdude to talk directly to the terminal (so no tar | ssh
# tricks here).

ssh_control_path = "ControlPath=avrdude-ssh-%C"

ssh_master_cmdline = [
	"ssh",
	"-o", "ControlMaster=yes",
	"-o", "ControlPersist=no",
	"-o", ssh_control_path,
	args.hostname,
]

ssh_slave_cmdline = [
	"ssh",
	"-o", "ControlMaster=no",
	"-o", ssh_control_path,
	args.hostname,
]

# Open the master connection. Connect its stdin with a pipe to our process, so
# that if we die, we won't leave an indefinitely hanging ssh session.
# stdout is redirected to stderr here and everywhere below, because the client
# may be expecting avrdude's output in stdout; don't mess it up.
# NOTE: we use `cat` as command to avoid launching a surplus shell instance
#       because it is only used to have something to read from our stdin
#       (so that ssh gets a SIGPIPE and dies accordingly; that is, we can't just
#        say `-N`).

ssh_master = subprocess.Popen(ssh_master_cmdline + [ "cat" ],
                              stdin=subprocess.PIPE,
                              stdout=sys.stderr,
                              universal_newlines=True)

# Create a temporary directory on the remote (sftp is not powerful enough for
# mktemp).

ssh_mktemp = subprocess.run(ssh_slave_cmdline + [ "mktemp", "-d" ],
                            stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE,
                            universal_newlines=True,
                            check=True)

work_path = ssh_mktemp.stdout.rstrip()

# Prepare a sftp connection.
# We can't use one sftp connection for everything because we don't get feedback
# from sftp command regarding individual commands. Hence, we start a sftp
# instance, submit upload commands, wait for the process to terminate,
# then execute avrdude, then (if needed) start a second sftp instance for
# download.

sftp_cmdline = [
	"sftp",
	"-o", "ControlMaster=no",
	"-o", ssh_control_path,
	"-b", "-",
	args.hostname,
]

# Upload: cd to the temporary directory and put all input files.

sftp_stdin = [ f"cd '{work_path}'" ]
sftp_need_upload = False

for op in args.ops:
	if op.need_copy() and op.is_input():
		sftp_need_upload = True
		sftp_stdin += [ f"put '{op.path}' '{op.remote_path}'" ]

sftp_stdin += [ "quit" ]

if sftp_need_upload:
	print(f"running sftp for upload: {sftp_stdin}")
	sftp = subprocess.run(sftp_cmdline,
                              input="\n".join(sftp_stdin),
                              stdout=sys.stderr,
                              universal_newlines=True,
                              check=True)

# Run avrdude to perform tasks.
# Don't forget to cd to the temporary directory.

avrdude_cmdline = [ "cd", work_path, ";", "avrdude" ]
avrdude_cmdline += remainder
for op in args.ops:
	avrdude_cmdline += [ "-U", op.remote() ]

ssh_avrdude = subprocess.run(ssh_slave_cmdline + ["cd", work_path, ";" ] + avrdude_cmdline,
                             stdin=sys.stdin,
                             stdout=sys.stdout,
                             stderr=sys.stderr,
                             universal_newlines=True,
                             check=True)

# Download: cd to a temporary directory and get all output files.

sftp_stdin = [ f"cd '{work_path}'" ]
sftp_need_download = False

for op in args.ops:
	if op.need_copy() and op.is_output():
		sftp_need_download = True
		sftp_stdin += [ f"get '{op.remote_path}' '{op.path}'" ]

sftp_stdin += [ "quit" ]

if sftp_need_download:
	print(f"running sftp for download: {sftp_stdin}")
	sftp = subprocess.run(sftp_cmdline,
	                      input="\n".join(sftp_stdin),
	                      stdout=sys.stderr,
	                      universal_newlines=True,
	                      check=True)
