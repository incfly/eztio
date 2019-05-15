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

function vm_instance_ip() {
  vm=${1:-nonexisting-vm-name}
  gcloud --format="value(networkInterfaces[0].networkIP)" \
    compute instances describe ${vm}
}

function meshexp_config() {
  cluster=${1:-gke-cluster-name}
  connectivity=${2:-gateway}
  # version=${3:-1.12}
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${cluster} --format "value(servicesIpv4Cidr)")
  rm -rf meshexp.env cluster.env
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\nISTIO_INBOUND_PORTS=$1" > cluster.env
  cat <<EOT >> meshexp.env
GATEWAY_IP=$(istio_gateway_ip)
ISTIO_DEBIAN_URL='https://storage.googleapis.com/istio-release/releases/${ISTIO_RELEASE}/deb/istio-sidecar.deb'
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
    vmexec.sh cluster.env key.pem meshexp.env kubedns ${vm}:~
}

# Script to install istio components for the raw VM.

# Environment variable pointing to the generated Istio configs and binaries.
# TODO: use curl or tar to fetch the artifacts.
ISTIO_STAGING=${ISTIO_STAGING:-.}

function istioVersionSource() {
  echo "Sourced ${ISTIO_STAGING}/istio.VERSION"
  cat "${ISTIO_STAGING}/istio.VERSION"
  # shellcheck disable=SC1090
  source "${ISTIO_STAGING}/istio.VERSION"
}

function istioInstall() {
  echo "*** Fetching istio packages..."
  # Current URL for the debian files artifacts. Will be replaced by a proper apt repo.
  rm -f istio-sidecar.deb
  curl -f -L "${PILOT_DEBIAN_URL}/istio-sidecar.deb" > "${ISTIO_STAGING}/istio-sidecar.deb"

  # Install istio binaries
  dpkg -i "${ISTIO_STAGING}/istio-sidecar.deb"
  mkdir -p /etc/certs
  cp ${ISTIO_STAGING}/*.pem /etc/certs

  # Cluster settings - the CIDR in particular.
  cp "${ISTIO_STAGING}/cluster.env" /var/lib/istio/envoy

  chown -R istio-proxy /etc/certs
  chown -R istio-proxy /var/lib/istio/envoy

  # Useful to test VM extension to istio
  apt-get --no-install-recommends -y install host
}

function istioRestart() {
  systemctl restart istio-auth-node-agent
  systemctl restart istio
}

# if [[ ${1:-} == "initNetwork" ]] ; then
#   istioNetworkInit
# elif [[ ${1:-} == "istioInstall" ]] ; then
#   istioVersionSource
#   istioInstall
#   istioRestart
# elif [[ ${1:-} == "help" ]] ; then
#   echo "$0 initNetwork: Configure DNS"
#   echo "$0 istioInstall: Install istio components"
# else
#   istioVersionSource
#   istioNetworkInit
#   istioInstall
#   istioRestart
# fi


eval "${@:1}"