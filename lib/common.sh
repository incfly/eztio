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
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${cluster} --format "value(servicesIpv4Cidr)")
  rm -rf mesh-expansion.env cluster.env
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\nISTIO_INBOUND_PORTS=$1" > cluster.env
  cat <<EOT >> mesh-expansion.env
GATEWAY_IP=$(istio_gateway_ip)
EOT
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
  local vm=${1:-vm-instancename}
  gcloud compute scp mesh-expansion.env bin/istio-gce.sh \
    cert-chain.pem root-cert.pem cluster.env key.pem ${vm}:~
}

eval "${@:1}"