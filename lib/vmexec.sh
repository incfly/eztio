#!/bin/bash

function meshexp_dnsinit() {
  # dns init
  export $(cat meshexp.env | xargs)
  # skip dns stuff first...
  sudo apt-get update
  sudo apt-get --no-install-recommends -y install python2
  # sudo apt-get --no-install-recommends -y install dnsmasq
  # Copy config files for DNS
  # chmod go+r "kubedns"
  # sudo cp "kubedns" /etc/dnsmasq.d
  # sudo systemctl restart dnsmasq
  echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" | sudo tee -a /etc/hosts
  curl ${ISTIO_DEBIAN_URL}  -L > istio-sidecar.deb
  sudo dpkg -i istio-sidecar.deb
  sudo mkdir -p /etc/certs /var/lib/istio/envoy
  sudo cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  sudo cp cluster.env /var/lib/istio/envoy
  sudo systemctl start istio
  sudo systemctl start istio-auth-node-agent
}

eval "${@:1}"