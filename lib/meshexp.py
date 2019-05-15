import os
import sys
import subprocess
import lib.cluster as k8s
import lib.cli_helper as helper

def service_entry():
  f = open('service-entry.yaml', 'w')
  f.write('''apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: {svc}-rawvm
spec:
   hosts:
   - {svc}.default.svc.cluster.local
   ports:
   - number: 8080
     name: {protocol}-{svc}
     protocol: {protocol}
   resolution: STATIC
   endpoints:
    - address: {ip}
      labels:
        registry: rawvm
      ports:
        {protocol}-{svc}: {port}'''.format(
          svc='vmhttp',
          protocol='http',
          port=8080,
          ip='10.128.0.17',
        ))
  f.close()

def k8s_service():
  f = open('k8s-service.yaml', 'w')
  f.write('''apiVersion: v1
kind: Service
metadata:
  name: {svc}
  namespace: default
spec:
  ports:
  - name: http
    port: 8080
    protocol: TCP
  selector:
    app: httpbin
'''.format(svc='vmhttp', port=8080))
  f.close()

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
    exec = subprocess.Popen(
      'bash -x lib/common.sh meshexp_vmexec "bash -x ~/vmexec.sh meshexp_dnsinit"'.split(' ')
    )
    exec.wait()
    return
  if operation == 'add':
    service_entry()
    k8s_service()
    # add_svc = subprocess.Popen(
    #   'bash -x lib/common.sh meshexp_addservice vmhttp 8080'.split(' ')
    # )
    # add_svc.wait()
  if operation == 'remove':
    remove = subprocess.Popen(
      ('gcloud compute instances delete ' + vm).split(' ')
    )
    remove.wait()
