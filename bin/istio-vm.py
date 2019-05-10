#!/usr/local/bin/python3
# This program provides common operations for Istio mesh expansion for incfly@ personal purpose.
# Hopefully some features can get into offical tooling, istioctl eventually.
# Sample usage

# istiomgr init <default-project> <default-zone> <cluster-name>
#   install config in .istiovm/ folder
# istiomgr install <version> <helm-flag>?
#   install istio with some options.
# istiomgr meshexp setup <vm-instance-name>
#   setup meshexp instance.
# istiomgr meshexp add <service> <port> // invoking istioctl eventually.
# istiomgr meshexp remove <service> // invoking istioctl eventually.
# istiomgr status // reporting istio status from .istio/ directory

import argparse
import urllib.request


def meshexp_handler(args):
  print('meshexp', args)


def install_handler(args):
  version = args.version
  print('jianfeih install istio version %s' % version)
  # Download istio first
  local_filename, headers = urllib.request.urlretrieve(
    'https://github.com/istio/istio/releases/download/1.1.2/istio-1.1.2-linux.tar.gz',
    './istio-1.1.2-linux.tar.gz')
# class InstallAction(argparse.Action):
#   def __call__(self, parser, namespace, values, option_string=None):
#     print('jianfeih debug ', parser, namespace, values)
  

def setup_parser():
  parser = argparse.ArgumentParser(
    description='istiomgr is a program for daily istio management.')
  sub_parser = parser.add_subparsers()
  install_parser = sub_parser.add_parser(
    'install',
    help='Install Istio with some option.')
  install_parser.add_argument('version', type=str,
    help='istio version to install, e.g. 1.1.2')
  install_parser.set_defaults(func=install_handler)
  # meshexp_parser = sub_parser.add_parser('meshexp')
  # meshexp_parser.add_argument(
  #   'operation', type=str,
  #   help='actions for the mesh expansion, add/remove/setup')
  # meshexp_parser.set_defaults(func=meshexp_handler)
  args = parser.parse_args()
  print(args)
  # parser.func(args)
  args.func(args)


setup_parser()