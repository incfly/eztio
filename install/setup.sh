export proj="${proj:-jianfeih-test}"
export zone="${zone:-us-central1-a}"
export CLUSTER_NAME="${CLUSTER_NAME:-istio-meshexp}"
export GCE_NAME="${GCE_NAME:-istio-vm}"
export VM_SCRIPT_URL="https://raw.githubusercontent.com/incfly/istio-gce/master/install/gce-setup.sh"
export DOWNLOAD_URL="https://github.com/istio/istio/releases/download/1.1.0-snapshot.6/istio-1.1.0-snapshot.6-osx.tar.gz"
export OUT_DIR="tmp"
# TODO: fix this hardcoding.
export ISTIO_ROOT="${OUT_DIR}/istio-1.1.0-snapshot.6"

export GATEWAY_IP="${GATEWAY_IP:-35.238.212.236}"
export VM_SERVICE_HOST="${SERVICE_HOST-productpage.default.svc.cluster.local}"
export VM_SERVICE_IP="${SERVICE_IP-10.51.248.227}"

# Status: VM -> productpage:9080 works and sleep curl VM works as well.
# We must create clusters sequentially without specifying --async, otherwise will fail.
function create_clusters() {
  echo "Create GKE cluster, name ${CLUSTER_NAME}"
  scope="https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append"
	gcloud container clusters create $CLUSTER_NAME --zone $zone --username "admin" \
--machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
--scopes $scope --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring

  echo "Create GCE instance, ${GCE_NAME}..."
  gcloud compute instances create ${GCE_NAME}
}

function create_cluster_admin() {
	gcloud container clusters get-credentials $CLUSTER_NAME --zone $zone
	kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account) || true
}

function download() {
	rm -rf $OUT_DIR && mkdir $OUT_DIR
  local outfile="${OUT_DIR}/istio-download.tgz"
  if [[ ! -f "${outfile}" ]]; then
    wget –quiet -O "${outfile}" "${DOWNLOAD_URL}"
  fi
  tar xf $outfile -C ${OUT_DIR}
  echo $outfile
}

function install_istio() {
	kubectl config use-context "gke_${proj}_${zone}_${CLUSTER_NAME}"
	download
  pushd $ISTIO_ROOT
	for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
	helm repo add istio.io "https://storage.googleapis.com/istio-prerelease/daily-build/master-latest-daily/charts"
	helm dep update install/kubernetes/helm/istio
	helm template install/kubernetes/helm/istio --name istio --namespace istio-system \
  --set global.meshExpansion.enabled=true > ./istio.yaml
	kubectl create ns istio-system
	kubectl apply -f ./istio.yaml
	kubectl label namespace default istio-injection=enabled
	popd
}


function update_vmconfig() {
  export GATEWAY_IP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo $GATEWAY_IP
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${CLUSTER_NAME} --zone $zone --format "value(servicesIpv4Cidr)")
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\n" > cluster.env
  echo "ISTIO_INBOUND_PORTS=3306,8080" >> cluster.env

  kubectl -n istio-system get secrets istio.default  \
    -o jsonpath='{.data.root-cert\.pem}' |base64 --decode > root-cert.pem
  kubectl -n istio-system get secrets istio.default  \
      -o jsonpath='{.data.key\.pem}' |base64 --decode > key.pem
  kubectl -n istio-system get secrets istio.default  \
        -o jsonpath='{.data.cert-chain\.pem}' |base64 --decode > cert-chain.pem
  
   gcloud compute scp gce-setup.sh cert-chain.pem root-cert.pem cluster.env key.pem istio-vm:/home/jianfeih
}

# Deploy bookinfo in two clusters.
function deploy_bookinfo() {
	pushd $ISTIO_ROOT
	kubectl config use-context "gke_${proj}_${zone}_${CLUSTER_NAME}"
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
	PRODUCT_PAGE_IP=$(kubectl get svc productpage -o jsonpath='{.spec.clusterIP}')
	popd
}

# add_vmservice $service_name $ip $port
# add_vmservice vmhttp 10.128.15.222 8080
function add_service() {
  svc=$1
  ip=$2
  port=$3
	kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: ${svc}
spec:
   hosts:
   - ${svc}.default.svc.cluster.local
   ports:
   - number: $port
     name: http
     protocol: HTTP
   resolution: STATIC
   endpoints:
    - address: $ip
      ports:
        http: ${port}
EOF
  # bin/istioctl  register vmhttp 10.128.15.222 8080
  $ISTIO_ROOT/bin/istioctl register $svc $ip $port
}

# remove_service vmhttp 10.128.15.222 8080
function remove_service() {
  svc=$1
  ip=$2
  kubectl delete ServiceEntry $svc
  $ISTIO_ROOT/bin/istioctl deregister $svc $ip
}

# k2vm vmhttp:8080
function k2vm() {
  kubectl exec -it $(kubectl get po  -l app=sleep -ojsonpath='{.items[0].metadata.name}') -- curl $1
}

# TODO: bookinfo is not mentioned in the new guide.
function cleanup_all() {
	gcloud container clusters delete ${CLUSTER_NAME}
  gcloud compute instances delete ${GCE_NAME}
}

# TODO: just delete Istio.
function cleanup_istio() {
	kubectl config use-context "gke_${proj}_${zone}_${CLUSTER_NAME}"
	kubectl delete ns istio-system
}

function do_all() {
	create_clusters
	create_cluster_admin
	# install_istio
	# Really workaround, remote istio cluster may not be ready.
	# sleep 60
	# deploy_bookinfo
	# get_verify_url
}


function gce_setup() {
  vm_config=$(printenv | ack 'GATEWAY_IP|VM_SERVICE_HOST|VM_SERVICE_IP|VM_SERVICE_PORT|ECHO_ENV' | tr '\n' ' ')
  printenv
  echo "Passing config to VM $vm_config"
  gcloud compute ssh ${GCE_NAME} -- "$vm_config bash ~/gce-setup.sh $@"
}

case $1 in
  setup)
    do_all
    ;;

  update_vmconfig)
     update_vmconfig
     ;;

   gce-setup)
     gce_setup "${@:2}"
     ;;

  add_service)
    add_service "${@:2}"
    ;;

  remove_service)
    remove_service "${@:2}"
    ;;

  k2vm)
    k2vm "${@:2}"
    ;;

  vm2k)
    vm2k "${@:2}"
    ;;
  
  cleanup)
    cleanup
    ;;
esac
