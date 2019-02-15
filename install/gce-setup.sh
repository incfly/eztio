#!/bin/bash

# This script is supposed to run on a GCE instance.
function setup() {
  sudo su
  curl https://storage.googleapis.com/istio-release/releases/1.1.0-snapshot.6/deb/istio-sidecar.deb  -L > istio-sidecar.deb
  dpkg -i istio-sidecar.deb
  # TODO: fix this by passing the IP.
  GWIP="1.1.1.1"
  PRODUCT_PAGE_IP="1.1.1.1"
  echo "$GWIP istio-citadel istio-pilot istio-pilot.istio-system" >> /etc/hosts
  echo "$PRODUCT_PAGE_IP productpage.default.svc.cluster.local" >> /etc/hosts
  mkdir -p /etc/certs
  cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  cp cluster.env /var/lib/istio/envoy
  # Then kill this...
  node_agent
}


