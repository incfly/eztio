import os
import sys
import subprocess

def gke_cluster_name():
  kc = subprocess.Popen(
    'kubectl config current-context'.split(' '),
    stdout=subprocess.PIPE)
  context = kc.stdout.readline().decode('utf-8').rstrip()
  return context.split('_')[3]
