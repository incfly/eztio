#!/usr/bin/python
# This program provides common operations for Istio mesh expansion for incfly@ personal purpose.
# Hopefully some features can get into offical tooling, istioctl eventually.
# Sample usage

# istio-gce init <default-project> <default-zone> <cluster-name>
# install config in .istiovm/ folder
# istio-gce instance setup <gce-name>
# istio-gce service add <service> <port> // invoking istioctl eventually.
# istio-gce service delete <service>
# istio-gce status // reporting the mesh expansion status in terms of enrolled vm.
# 
# istio-gce misc gce-image create --debian-url="https://a.b.c"
# for incfly@ personal sake.

import argparse

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