#!/bin/bash

function meshexp_dnsinit() {
  export $(cat mesh-expansion.env | xargs)
  apt-get --no-install-recommends -y install dnsmasq
  # Copy config files for DNS
  chmod go+r "${ISTIO_STAGING}/kubedns"
  cp "${ISTIO_STAGING}/kubedns" /etc/dnsmasq.d
  systemctl restart dnsmasq
}

eval "${@:1}"