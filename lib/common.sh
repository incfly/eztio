#!/bin/bash


function helm_install() {
  local version=${1:-1.1.2}
  local download_dir=${2:-downloads}
  pushd ${download_dir}/istio-${version}
  kubectl create namespace istio-system
  helm template install/kubernetes/helm/istio-init --name istio-init \
    --namespace istio-system | kubectl apply -f -
  helm template install/kubernetes/helm/istio \
    --name istio --namespace istio-system \
    --values install/kubernetes/helm/istio/values-istio-demo.yaml \
    --set global.meshExpansion.enabled=true > ./istio.yaml
  kubectl apply -f istio.yaml
  popd
}

function uninstall_istio() {
  kubectl delete ns istio-system
}

function istio_gateway_ip() {
  GWIP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo $GWIP
}

# TODO: remove this hardcoded abc...
function vm_instance_ip() {
  vm=${1:-abc}
  gcloud --format="value(networkInterfaces[0].networkIP)" \
    compute instances describe ${vm}
}

function meshexp_config() {
  local cluster=${1:-gke-cluster-name}
  local connectivity=${2:-gateway}
  local port=${3:-8080}
  # version=${3:-1.12}
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${cluster} --format "value(servicesIpv4Cidr)")
  rm -rf meshexp.env cluster.env
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\nISTIO_INBOUND_PORTS=${port}" > cluster.env
  cat <<EOT >> meshexp.env
GATEWAY_IP=$(istio_gateway_ip)
ISTIO_DEBIAN_URL='https://storage.googleapis.com/istio-release/releases/1.1.2/deb/istio-sidecar.deb'
EOT
  # Multiple tries, it may take some time until the controllers generate the IPs
  if [ "${connectivity}" == "ilb" ]; then
    PILOT_IP=$(kubectl get -n "$NS" service istio-pilot-ilb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    ISTIO_DNS=$(kubectl get -n kube-system service dns-ilb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    MIXER_IP=$(kubectl get -n "$NS" service mixer-ilb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    CITADEL_IP=$(kubectl get -n "$NS" service citadel-ilb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  else
    GATEWAY_IP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    PILOT_IP=${GATEWAY_IP}
    # TODO: support DNS.
    ISTIO_DNS=${GATEWAY_IP}
    MIXER_IP=${GATEWAY_IP}
    CITADEL_IP=${GATEWAY_IP}
  fi

  if [ "${PILOT_IP}" == "" ] || [  "${ISTIO_DNS}" == "" ] || [ "${MIXER_IP}" == "" ] || [ "${CITADEL_IP}" == "" ] ; then
    echo "Failed to create ILBs"
    exit 1
  fi

  echo "Pilot IP, Istio DNS ${ISTIO_DNS}, mixer ${MIXER_IP}, citadel ${CITADEL_IP}"

  #/etc/dnsmasq.d/kubedns
  {
    # DNS does not work fro Gateway based model since that requires mTLS.
    # We might need to configure dnsmasq differently.
    echo "server=/svc.cluster.local/$ISTIO_DNS"
    echo "address=/istio-policy/$MIXER_IP"
    echo "address=/istio-telemetry/$MIXER_IP"
    echo "address=/istio-pilot/$PILOT_IP"
    echo "address=/istio-citadel/$CITADEL_IP"
    # Also generate host entries for the istio-system. The generated config will work with both
    # 'cluster-wide' and 'per-namespace'.
    echo "address=/istio-policy.istio-system/$MIXER_IP"
    echo "address=/istio-telemetry.istio-system/$MIXER_IP"
    echo "address=/istio-pilot.istio-system/$PILOT_IP"
    echo "address=/istio-citadel.istio-system/$CITADEL_IP"
  } > kubedns
}

function meshexp_keycert() {
  kubectl get secrets istio.default  \
  -o jsonpath='{.data.root-cert\.pem}' | base64 --decode > root-cert.pem
  kubectl get secrets istio.default  \
      -o jsonpath='{.data.key\.pem}' | base64 --decode > key.pem
  kubectl get secrets istio.default  \
        -o jsonpath='{.data.cert-chain\.pem}' |base64 --decode > cert-chain.pem
}

function meshexp_copy() {
  local vm=${1:-meshexp-vm}
  gcloud compute scp cert-chain.pem root-cert.pem \
    lib/vmexec.sh cluster.env key.pem meshexp.env kubedns ${vm}:~
}

function meshexp_vmexec() {
  local cmd=${1:-echo hello}
  gcloud compute ssh abc --command "${cmd}"
}

eval "${@:1}"