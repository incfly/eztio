#!/bin/bash

function meshexp_dnsinit() {
  # dns init
  export $(cat mesh-expansion.env | xargs)
  sudo apt-get --no-install-recommends -y install dnsmasq
  # Copy config files for DNS
  chmod go+r "kubedns"
  sudo cp "kubedns" /etc/dnsmasq.d
  sudo systemctl restart dnsmasq

  curl "https://storage.googleapis.com/istio-release/releases/1.1.0/deb/istio-sidecar.deb"  -L > istio-sidecar.deb
  sudo dpkg -i istio-sidecar.deb
  # echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" | sudo tee -a /etc/hosts
  sudo mkdir -p /etc/certs /var/lib/istio/envoy
  sudo cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  sudo cp cluster.env /var/lib/istio/envoy
  sudo systemctl start istio
  sudo systemctl start istio-auth-node-agent
}

eval "${@:1}"