import urllib.request
import os
import sys
import subprocess


def download_url(version):
  return (
    'https://github.com/istio/istio/releases/download/'
    '{0}/istio-{0}-linux.tar.gz'
  ).format(version)


def filename(version):
  return 'downloads/istio-%s-linux.tar.gz' % version


def download_istio(version : str):
  file_name = filename(version)
  if os.path.isfile(file_name):
    print('Istio version %s exists, skip downloading...' % version)
    return
  print('Downloading Istio version %s' % version)
  # Download Istio first.
  if not os.path.exists('downloads'):
    os.mkdir('downloads')
  urllib.request.urlretrieve(download_url(version), file_name)


def install_istio(version : str):
  kube = subprocess.Popen(
    ['bash', '-x', 'lib/common.sh', 'helm_install', version])
  kube.wait()


def install_handler(args):
  download_istio(args.version)
  install_istio(args.version)

def uninstall_handler(args):
  kube = subprocess.Popen(
    'bash -x lib/common.sh uninstall_istio'.split(' '))
  kube.wait()