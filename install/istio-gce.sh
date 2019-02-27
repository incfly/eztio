# TODO, dig @10.52.0.3 -p 53 paymentservice.default.svc.cluster.local, the ip is
# the node ip from `kubectl describe services kube-dns -n kube-system`
export GCP_PROJECT="${GCP_PROJECT:-jianfeih-test}"
export GCP_ZONE="${zone:-us-central1-a}"
export GKE_NAME="${GKE_NAME:-istio-meshexp}"
export GCE_NAME="${GCE_NAME:-istio-vm}"
export DOWNLOAD_URL=${DOWNLOAD_URL-https://github.com/istio/istio/releases/download/1.1.0-rc.0/istio-1.1.0-rc.0-linux.tar.gz}
export OUT_DIR="tmp"

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

  gcloud container clusters get-credentials $GKE_NAME --zone $zone
	kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account) || true
}

function istio_root() {
  find ${OUT_DIR} -maxdepth 1  -mindepth 1 -type d
}

# Create a GCE instance with container optimized image selection.
# Make gcr.io/PROJECT-ID public for now...
function create_gce() {
  name=$1
  if `gcloud compute instances list | grep $name`; then
    echo "GCE instance ${name} already exists, skip creating..."
  fi
  echo "Create GCE instance, ${name}..."
  gcloud compute instances create ${name} \
     --image-project=ubuntu-os-cloud  --image=ubuntu-1604-xenial-v20190212
#    --image-project=coreos-cloud  --image=coreos-alpha-2051-0-0-v20190211
#   cos does not have dpkg package manager.
#   1804 does not have docker.
  # On VM... (tag is needed), latest does not work.
  # docker run --rm gcr.io/jianfeih-test/productcatalogservice:2f7240f
}

function vm_instance_ip() {
  gcloud --format="value(networkInterfaces[0].networkIP)" compute instances describe  ${GCE_NAME}
}

function download() {
  outdir=$1
  download_url=$2
  rm -rf ${outdir} && mkdir ${outdir}
  local outfile="${outdir}/istio-download.tgz"
  if [[ ! -f "${outfile}" ]]; then
    wget –quiet -O "${outfile}" "${download_url}"
  fi
  tar xf $outfile -C ${OUT_DIR}
  echo $outfile
}

function install_istio() {
	kubectl config use-context "gke_${GCP_PROJECT}_${GCP_ZONE}_${GKE_NAME}"
	download ${OUT_DIR} ${DOWNLOAD_URL}
  pushd $(istio_root)
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
  ISTIO_SERVICE_CIDR=$(gcloud container clusters describe ${GKE_NAME} --zone $GCP_ZONE --format "value(servicesIpv4Cidr)")
  echo -e "ISTIO_CP_AUTH=MUTUAL_TLS\nISTIO_SERVICE_CIDR=$ISTIO_SERVICE_CIDR\n" > cluster.env
  # TODO: This must be refactored
  echo "ISTIO_INBOUND_PORTS=3306,3550" >> cluster.env

  kubectl -n istio-system get secrets istio.default  \
    -o jsonpath='{.data.root-cert\.pem}' |base64 --decode > root-cert.pem
  kubectl -n istio-system get secrets istio.default  \
      -o jsonpath='{.data.key\.pem}' |base64 --decode > key.pem
  kubectl -n istio-system get secrets istio.default  \
        -o jsonpath='{.data.cert-chain\.pem}' |base64 --decode > cert-chain.pem
  
   gcloud compute scp istio-gce.sh cert-chain.pem root-cert.pem cluster.env key.pem ${vm}:~
}

# Deploy bookinfo in two clusters.
function deploy_bookinfo() {
	pushd $(istio_root)
	kubectl config use-context "gke_${proj}_${zone}_${GKE_NAME}"
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
	PRODUCT_PAGE_IP=$(kubectl get svc productpage -o jsonpath='{.spec.clusterIP}')
	popd
}

# add_service $service_name $port
# add_service vmhttp 10.128.15.222 8080 HTTP
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
  $(istio_root)/bin/istioctl register $svc $ip $port
}

# remove_service vmhttp
function remove_service() {
  svc=$1
  ip=$(vm_instance_ip)
  echo "Remove VM service, name = ${svc}, IP ${ip}, protocol ${protocol}"
  kubectl delete ServiceEntry $svc
  $(istio_root)/bin/istioctl deregister $svc $ip
}

# k2vm vmhttp:8080
function k2vm() {
  kubectl exec -it $(kubectl get po  -l app=sleep -ojsonpath='{.items[0].metadata.name}') -- curl $1
}

# TODO: bookinfo is not mentioned in the new guide.
function cleanup_all() {
	gcloud container clusters delete ${GKE_NAME}
  gcloud compute instances delete ${GCE_NAME}
}

# TODO: just delete Istio.
function cleanup_istio() {
	kubectl config use-context "gke_${proj}_${zone}_${GKE_NAME}"
	kubectl delete ns istio-system
}

function setup() {
  create_clusters ${GKE_NAME} ${GCP_ZONE}
  create_gce ${GCE_NAME}
  install_istio
}


function gce_setup() {
  # sudo usermod -aG docker $USER
  update_vmconfig ${GCE_NAME}
  vmenv=$(printenv | ack 'GATEWAY_IP|VM_SERVICE_HOST|VM_SERVICE_IP|VM_SERVICE_PORT|ECHO_ENV' | tr '\n' ' ')
  echo "Passing env var to VM $vmenv"
  gcloud compute ssh ${GCE_NAME} -- "$vmenv sudo bash ~/istio-gce.sh gcerun_setup"
}


# gceru_xx functions are supposed to execute on GCE instance.
#
function gcerun_setup() {
  echo "gce setup"
  # Unable to automate Docker install part...
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  docker version
  curl https://storage.googleapis.com/istio-release/releases/1.1.0-snapshot.6/deb/istio-sidecar.deb  -L > istio-sidecar.deb
  dpkg -i istio-sidecar.deb
  echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" >> /etc/hosts
  mkdir -p /etc/certs /var/lib/istio/envoy
  cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  cp cluster.env /var/lib/istio/envoy
  systemctl start istio
  systemctl start istio-auth-node-agent
}

function gcerun_addservice() {
  if [[ -z "${SERVICE_HOST}" || -z "${SERVICE_IP}" ]]; then
    echo "Empty SERVICE_HOST or SERVICE_IP, please set."
    return
  fi
  echo "Add service from kubernetes clusters to the VM, Host ${SERVICE_HOST} ${SERVICE_IP}"
  sudo echo "${SERVICE_IP} ${SERVICE_HOST}" >> /etc/hosts
}

# TODO: not tested yet.
function gce_start_helloworld() {
  kill $(ps aux | grep 'SimpleHTTPServer' | awk '{print $2}')
  python -m SimpleHTTPServer 8080 > http-server.output 2>&1 &
}

function echo_env() {
  echo "env is " $ECHO_ENV
}

function gcerun_cleanup() {
  sudo systemctl stop istio
  sudo systemctl stop istio-auth-node-agent
  sudo sed -i  '/istio\|cluster.local/d' /etc/hosts
}


# Example: vm_exec docker run -d  -p 3550:3550  gcr.io/jianfeih-test/productcatalogservice:2f7240f
function vm_exec() {
  gcloud compute ssh ${GCE_NAME} -- "$@"
}

case $1 in
  setup)
    setup
    ;;

  vm_exec)
    vm_exec "${@:2}"
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

  gcerun_setup)
    gcerun_setup
    ;;

  *)
    echo $"Usage: $0 {setup|cleanup|vm2k|k2vm|gce_setup}"
    # exit 1
esac
