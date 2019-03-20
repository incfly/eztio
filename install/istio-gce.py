#!/usr/bin/python
import argparse


def bash_cmd(args):


def setup_handlers(args):
  if args.operation == 'cluster':
    print 'setup cluster'
  elif args.operation == 'vm':
    print 'setup vm'
  else:
    print 'invalid command', args.operation


def service_handlers(args):
  print 'manage service ', args


parser = argparse.ArgumentParser(description='Process some integers.')
parser.add_argument('-vm', dest='vm_name')

subparsers = parser.add_subparsers(help='subparser help')

setup = subparsers.add_parser('setup')
setup.add_argument('operation')
setup.set_defaults(handler=setup_handlers)

service = subparsers.add_parser('service')
service.add_argument('operation')
service.set_defaults(handler=service_handlers)

result = parser.parse_args()
print result
result.handler(result)