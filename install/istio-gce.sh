# TODO, dig @10.52.0.3 -p 53 paymentservice.default.svc.cluster.local, the ip is
# the node ip from `kubectl describe services kube-dns -n kube-system`

export GCP_PROJECT="${GCP_PROJECT:-jianfeih-test}"
export GCP_ZONE="${zone:-us-central1-a}"
export GKE_NAME="${GKE_NAME:-microservice-demo}"
export GCE_NAME="${GCE_NAME:-istio-vm}"
export ISTIO_RELEASE=${ISTIO_RELEASE:-"istio-1.1.0-rc.0"}
export OUT_DIR="tmp"

function create_clusters() {
  cluster=$1
  zone=$2
  name=$1
  if gcloud container clusters list --zone ${zone} | grep $name; then
    echo "GKE instance ${name} already exists, skip creating..."
    return
  else 
    echo "Create GKE cluster, name ${cluster}, zone ${zone}"
    scope="https://www.googleapis.com/auth/compute","https://www.googleapis.com/auth/devstorage.read_only",\
"https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring",\
"https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly",\
"https://www.googleapis.com/auth/trace.append"
    # We must create clusters sequentially without specifying --async, otherwise will fail.
    gcloud container clusters create $cluster --zone $zone --username "admin" \
    --machine-type "n1-standard-2" --image-type "COS" --disk-size "100" \
    --scopes $scope --num-nodes "4" --network "default" --enable-cloud-logging --enable-cloud-monitoring
  fi 
  echo "Create Cluster role binding for cluster for Istio install..."
  gcloud container clusters get-credentials $GKE_NAME --zone $zone
	kubectl create clusterrolebinding cluster-admin-binding \
    --clusterrole=cluster-admin \
    --user=$(gcloud config get-value core/account) || true
}

function istio_root() {
  find ${OUT_DIR} -maxdepth 1  -mindepth 1 -type d | grep ${ISTIO_RELEASE}
}

function istio_gateway_ip() {
  GWIP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  echo $GWIP
}

# Create a GCE instance with container optimized image selection.
# Make gcr.io/PROJECT-ID public for now...
function create_gce() {
  name=$1
  if gcloud compute instances list | grep $name; then
    echo "GCE instance ${name} already exists, skip creating..."
    return
  fi
  echo "Create GCE instance, ${name}..."
  # This image has pre-installed package, Istio sidecar and Docker.
  # TODO: figure out how to share the image publicily.
  gcloud compute instances create ${name} \
    --image-project=jianfeih-test --image=istio-1-1-rc1-gce
    #  --image-project=ubuntu-os-cloud  --image=ubuntu-1604-xenial-v20190212
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
  download_url="https://github.com/istio/istio/releases/download/${ISTIO_RELEASE}-linux.tar.gz"
  mkdir -p ${outdir}
  # TODO: not use the same name.
  local outfile="${outdir}/istio-download.tgz"
  if [[ ! -f "${outfile}" ]]; then
    wget –quiet -O "${outfile}" "${download_url}"
  fi
  tar xf $outfile -C ${OUT_DIR}
  echo $outfile
}

function dumpconfig() {
  rm -rf mesh-expansion.env
  cat <<EOT >> mesh-expansion.env
GATEWAY_IP=$(istio_gateway_ip)
ISTIO_RELEASE=${ISTIO_RELEASE}
EOT
}

function install_istio() {
	kubectl config use-context "gke_${GCP_PROJECT}_${GCP_ZONE}_${GKE_NAME}"
	download ${OUT_DIR}
  pushd $(istio_root)
	for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl apply -f $i; done
  # TODO refactor this out.
	helm repo add istio.io "https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/release-1.1-latest-daily/charts/"
	helm dep update install/kubernetes/helm/istio
	helm template install/kubernetes/helm/istio --name istio --namespace istio-system \
    --set global.meshExpansion.enabled=true > ./istio.yaml
	kubectl create ns istio-system
	kubectl apply -f ./istio.yaml
	kubectl label namespace default istio-injection=enabled
	popd
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

# add_service $service_name $port $protocol
# add_service vmhttp 8080 HTTP
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
     name: ${protocol}-${svc}
     protocol: ${protocol}
   resolution: STATIC
   endpoints:
    - address: $ip
      ports:
        http: ${port}
EOF
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
function cleanup() {
	gcloud container clusters delete ${GKE_NAME}
  gcloud compute instances delete ${GCE_NAME}
}

# TODO: just delete Istio.
function uninstall_istio() {
  kubectl config use-context "gke_${proj}_${zone}_${GKE_NAME}"
  pushd $(istio_root)
	kubectl delete ns istio-system
  for i in install/kubernetes/helm/istio-init/files/crd*yaml; do kubectl delete -f $i; done
  popd
}

function setup() {
  create_clusters ${GKE_NAME} ${GCP_ZONE}
  create_gce ${GCE_NAME}
  install_istio
}

function gce_setup() {
  # sudo usermod -aG docker $USER
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
  
  dumpconfig
  gcloud compute scp mesh-expansion.env istio-gce.sh cert-chain.pem root-cert.pem cluster.env key.pem ${GCE_NAME}:~

  # Last step, execute setup on GCE VM.
  gcloud compute ssh ${GCE_NAME} -- "sudo bash -x ~/istio-gce.sh gcerun_setup"
}


# gceru_xx functions are supposed to execute on GCE instance.
# TODO: comment out the gcerun_setup since we use pre-created image, test it if works or not.
function gcerun_setup() {
  echo "GCE Setup running on GCE instance..."
  export $(cat mesh-expansion.env | xargs)
  # if [[ `which docker` ]]; then
  #   echo "Docker exists, skip installing..."
  # else
  #   # Unable to automate Docker install part, have to manually login to the GCE instance.
  #   rm -rf get-docker.sh && curl -fsSL https://get.docker.com -o get-docker.sh
  #   sh get-docker.sh
  #   docker version
  # fi
  # TODO: substr is hacky...
  echo "Installing $ISTIO_RELEASE, IP $GATEWAY_IP"
  # curl "https://storage.googleapis.com/istio-release/releases/${ISTIO_RELEASE:6}/deb/istio-sidecar.deb"  -L > istio-sidecar.deb
  # dpkg -i istio-sidecar.deb
  echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" | sudo tee -a /etc/hosts
  mkdir -p /etc/certs /var/lib/istio/envoy
  cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  cp cluster.env /var/lib/istio/envoy
  systemctl start istio
  systemctl start istio-auth-node-agent
}

# TODO: not tested yet.
function gce_start_helloworld() {
  kill $(ps aux | grep 'SimpleHTTPServer' | awk '{print $2}')
  python -m SimpleHTTPServer 8080 > http-server.output 2>&1 &
}

function gcerun_cleanup() {
  systemctl stop istio
  systemctl stop istio-auth-node-agent
  sed -i  '/istio\|cluster.local/d' /etc/hosts
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
    echo $GATEWAY_IP
    gcerun_setup
    ;;

  *)
    echo $"Usage: $0 {setup|cleanup|vm2k|k2vm|gce_setup}"
    # exit 1
esac
