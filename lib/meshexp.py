import os
import sys
import subprocess
import lib.cluster as k8s
import lib.cli_helper as helper

def handler(args):
  operation = args.operation
  vm = args.vm
  cluster = k8s.gke_cluster_name()
  if operation == 'init':
    config = subprocess.Popen(
      ('bash -x lib/common.sh meshexp_config ' + cluster).split(' '),
      stdout=subprocess.PIPE)
    config.wait()
    keycert = subprocess.Popen(
      'bash -x lib/common.sh meshexp_keycert'.split(' '),
      stdout=subprocess.PIPE)
    keycert.wait()
    return
  if operation == 'setup':
    # create instance if needed.
    # a = ('gcloud --format="value(networkInterfaces[0].networkIP)" '
    #   'compute instances describe ' + vm).split(' ')
    check = subprocess.Popen(
      ('bash lib/common.sh vm_instance_ip ' + vm).split(' '),
      stdout=subprocess.PIPE,
      stderr=subprocess.STDOUT)
    check.wait()
    if check.returncode != 0:
      if not helper.yes_no('GCE instance does not exists, creating'):
        print('Cant do anything, return...')
      create = subprocess.Popen(
        ('gcloud compute instances create {0} '
        '--image-project=ubuntu-os-cloud '
        '--image=ubuntu-1810-cosmic-v20190514').format(vm).split(' '))
      create.wait()
    # copy config over to the vm.
    copy = subprocess.Popen(
      ('bash -x lib/common.sh meshexp_copy ' + vm).split(' '))
    copy.wait()
    # execute bash on the vm
    # cmds = ('gcloud compute ssh {0} --command '
    #   '"sudo bash -x ~/vmexec.sh meshexp_dnsinit"').format(vm).split(' ')
    # print('debug ', cmds)
    exec = subprocess.Popen(
      'bash -x lib/common.sh meshexp_vmexec "bash -x ~/vmexec.sh meshexp_dnsinit"'.split(' ')
    )
    exec.wait()
    return
  if operation == 'remove':
    remove = subprocess.Popen(
      ('gcloud compute instances delete ' + vm).split(' ')
    )
    remove.wait()
