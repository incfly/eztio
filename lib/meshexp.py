import os
import sys
import subprocess
import lib.cluster as k8s
import lib.cli_helper as helper

def service_entry(vmname, svc : str, port : int, protocol : str,
  namespace='default'):
  vm_ip = instance_ip(vmname)
  file_name = 'output/meshexp-{0}.yaml'.format(svc)
  f = open(file_name, 'w')
  f.write('''apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: {svc}-rawvm
spec:
   hosts:
   - {svc}.{namespace}.svc.cluster.local
   ports:
   - number: {port}
     name: {protocol}-{svc}
     protocol: {protocol}
   resolution: STATIC
   endpoints:
    - address: {ip}
      labels:
        registry: rawvm
      ports:
        {protocol}-{svc}: {port}
---
apiVersion: v1
kind: Service
metadata:
  name: {svc}
  namespace: {namespace}
spec:
  ports:
  - name: http
    port: {port}
    protocol: TCP
'''.format(
          svc=svc,
          protocol='http',
          port=8080,
          ip=vm_ip,
          namespace=namespace
        ))
  f.close()
  return file_name

def instance_ip(name : str):
  ip = subprocess.Popen(
    'bash -x lib/common.sh vm_instance_ip {0}'.format(name).split(' '),
    stdout=subprocess.PIPE
  )
  ip_value = ip.stdout.readlines()[0].decode('utf-8').rstrip()
  return ip_value


def handler(args):
  operation = args.operation
  vm = args.vm
  namespace = args.namespace
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
    helper.invoke_cmd('bash -x lib/common.sh meshexp_copy %s' % vm)
    # execute bash on the vm
    helper.invoke_cmd('bash -x lib/common.sh meshexp_vmexec "bash -x ~/vmexec.sh meshexp_dnsinit"')
    return
  if operation == 'add':
    yaml = service_entry(
      vmname=vm, svc='vmhttp',
      port=8080, protocol='http',
    )
    helper.invoke_cmd('kubectl apply -f %s' % yaml)
  if operation == 'remove':
    remove = subprocess.Popen(
      ('gcloud compute instances delete ' + vm).split(' ')
    )
    remove.wait()
