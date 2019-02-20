export GCP_PROJECT="${GCP_PROJECT:-jianfeih-test}"
export GCP_ZONE="${zone:-us-central1-a}"
export CLUSTER_NAME="${CLUSTER_NAME:-istio-meshexp}"
export GCE_NAME="${GCE_NAME:-istio-vm}"
export VM_SCRIPT_URL="https://raw.githubusercontent.com/incfly/istio-gce/master/install/gce-setup.sh"
export DOWNLOAD_URL="https://github.com/istio/istio/releases/download/1.1.0-snapshot.6/istio-1.1.0-snapshot.6-linux.tar.gz"
export OUT_DIR="tmp"
# TODO: fix this hardcoding.
export ISTIO_ROOT="${OUT_DIR}/istio-1.1.0-snapshot.6"

export GATEWAY_IP="${GATEWAY_IP:-35.238.212.236}"
export VM_SERVICE_HOST="${SERVICE_HOST-productpage.default.svc.cluster.local}"
export VM_SERVICE_IP="${SERVICE_IP-10.51.248.227}"

# Status: VM -> productpage:9080 works and sleep curl VM works as well.
# We must create clusters sequentially without specifying --async, otherwise will fail.
function create_clusters() {
  cluster=$1
  zone=$2
  echo "Create GKE cluster, name ${cluster}, zone ${zone}"
  scope="https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append"
	gcloud container clusters create $cluster --zone $zone --username "admin" \
--machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
--scopes $scope --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring

  gcloud container clusters get-credentials $CLUSTER_NAME --zone $zone
	kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account) || true
}

# Create a GCE instance with container optimized image selection.
# Make gcr.io/PROJECT-ID public for now...
function create_gce() {
  name=$1
  echo "Create GCE instance, ${name}..."
  gcloud compute instances create ${name} \
    --image-project=coreos-cloud  --image=coreos-alpha-2051-0-0-v20190211
  # On VM... (tag is needed), latest does not work.
  # docker run --rm gcr.io/jianfeih-test/productcatalogservice:2f7240f
}

function vm_instance_ip() {
  gcloud compute instances describe ${GCE_NAME} | grep networkIP | sed 's/ //g'  | cut -d':' -f2
}

function download() {
  outdir=$1
  download_url=$2
  local outfile="${OUT_DIR}/istio-download.tgz"
  if [[ ! -f "${outfile}" ]]; then
    wget –quiet -O "${outfile}" "${download_url}"
  fi
  tar xf $outfile -C ${OUT_DIR}
  echo $outfile
}

function install_istio() {
  rm -rf ${OUT_DIR} && mkdir ${OUT_DIR}
	kubectl config use-context "gke_${GCP_PROJECT}_${GCP_ZONE}_${CLUSTER_NAME}"
	download ${OUT_DIR} ${DOWNLOAD_URL}
  pushd $ISTIO_ROOT
	for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
	helm repo add istio.io "https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/release-1.1-latest-daily/charts/"
	helm dep update install/kubernetes/helm/istio
	helm template install/kubernetes/helm/istio --name istio --namespace istio-system \
  --set global.meshExpansion.enabled=true > ./istio.yaml
	kubectl create ns istio-system
	kubectl apply -f ./istio.yaml
	kubectl label namespace default istio-injection=enabled
	popd
}


function update_vmconfig() {
  vm=$1
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${CLUSTER_NAME} --zone $GCP_ZONE --format "value(servicesIpv4Cidr)")
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\n" > cluster.env
  echo "ISTIO_INBOUND_PORTS=3306,8080" >> cluster.env

  kubectl -n istio-system get secrets istio.default  \
    -o jsonpath='{.data.root-cert\.pem}' |base64 --decode > root-cert.pem
  kubectl -n istio-system get secrets istio.default  \
      -o jsonpath='{.data.key\.pem}' |base64 --decode > key.pem
  kubectl -n istio-system get secrets istio.default  \
        -o jsonpath='{.data.cert-chain\.pem}' |base64 --decode > cert-chain.pem
  
   gcloud compute scp gce-setup.sh cert-chain.pem root-cert.pem cluster.env key.pem ${vm}:~
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

# add_vmservice $service_name $port
# add_vmservice vmhttp 10.128.15.222 8080 HTTP
function add_service() {
  svc=$1
  port=$2
  ip=$(vm_instance_ip)
  protocol=$3
  echo "Add VM service, name = ${svc}, IP ${ip}, protocol ${protocol}"
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
     protocol: ${protocol}
   resolution: STATIC
   endpoints:
    - address: $ip
      ports:
        http: ${port}
EOF
  # bin/istioctl  register vmhttp 10.128.15.222 8080
  $ISTIO_ROOT/bin/istioctl register $svc $ip $port
}

# remove_service vmhttp
function remove_service() {
  svc=$1
  ip=$(vm_instance_ip)
  echo "Remove VM service, name = ${svc}, IP ${ip}, protocol ${protocol}"
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

function setup() {
	create_clusters ${CLUSTER_NAME} ${GCP_ZONE}
  create_gce ${GCE_NAME}
}


function gce_setup() {
  update_vmconfig ${GCE_NAME}
  vmenv=$(printenv | ack 'GATEWAY_IP|VM_SERVICE_HOST|VM_SERVICE_IP|VM_SERVICE_PORT|ECHO_ENV' | tr '\n' ' ')
  echo "Passing env var to VM $vmenv"
  gcloud compute ssh ${GCE_NAME} -- "$vmenv bash ~/gce-setup.sh $@"
}

# example vm_exec docker run -d  -p 3550:3550  gcr.io/jianfeih-test/productcatalogservice:2f7240f
function vm_exec() {
  gcloud compute ssh ${GCE_NAME} -- "$@"
}

case $1 in
  setup)
    setup
    ;;

  vm_exec)
    vm_exec "${@}"
    ;;

  gce_setup)
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

  *)
    echo $"Usage: $0 {setup|cleanup|vm2k|k2vm|gce_setup}"
    exit 1

esac
