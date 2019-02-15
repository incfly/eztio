#!/bin/bash

# This script is supposed to run on a GCE instance.
function setup() {
  if [[ -z "${GATEWAY_IP}"]]; then
    echo "Please set GATEWAY_IP"
    return
  fi
  # for f in "root-cert.pe" "" ""; do
  #   if [[ ! -f $f ]]; then
  #     echo "Ensure file exists, $f"
  #   fi
  # done
  sudo su
  curl https://storage.googleapis.com/istio-release/releases/1.1.0-snapshot.6/deb/istio-sidecar.deb  -L > istio-sidecar.deb
  dpkg -i istio-sidecar.deb
  echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" >> /etc/hosts
  echo "$PRODUCT_PAGE_IP productpage.default.svc.cluster.local" >> /etc/hosts
  mkdir -p /etc/certs
  cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  cp cluster.env /var/lib/istio/envoy
  # Then kill this...
  node_agent
}

function add_kube_service() {
  if [[ -z "${SERVICE_HOST}" || -z "${SERVICE_IP}" ]]; then
    echo "Empty SERVICE_HOST or SERVICE_IP, please set."
    return
  fi
  echo "Add service from kubernetes clusters to the VM, Host ${SERVICE_HOST} ${SERVICE_IP}"
  sudo echo "${SERVICE_IP} ${SERVICE_HOST}" >> /etc/hosts
}
function stop_workload() {
  systemctl stop istio
  systemctl stop istio-auth-node-agent
  # TODO, remove all /etc/hosts stuff.
}
