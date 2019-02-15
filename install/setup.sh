export proj="${proj:-jianfeih-test}"
export zone="${zone:-us-central1-a}"
export CLUSTER_NAME="${CLUSTER_NAME:-istio-meshexp}"
export GCE_NAME="${GCE_NAME:-istio-vm}"
export RELEASE="${RELEASE:-release-1.1-20190209-09-16}"
export VM_SCRIPT_URL="https://raw.githubusercontent.com/incfly/istio-gce/master/install/gce-setup.sh"

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

# TODO: reuse from perf/istio/setup.sh
function download() {
  local DIRNAME="$1"
	rm -rf $DIRNAME && mkdir $DIRNAME
	https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/
  local url="https://gcsweb.istio.io/gcs/istio-prerelease/daily-build/${RELEASE}/istio-${RELEASE}-linux.tar.gz"
  local outfile="${DIRNAME}/istio-${RELEASE}.tgz"

  if [[ ! -f "${outfile}" ]]; then
    wget –quiet -O "${outfile}" "${url}"
  fi

  echo "${outfile}"
}

function install_istio() {
	kubectl config use-context "gke_${proj}_${zone}_${CLUSTER_NAME}"
	istio_tar=$(download ./tmp $RELEASE)
	tar xf $istio_tar -C ./tmp
	pushd tmp/istio-${RELEASE}
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


function prepare_gce_config() {
  GATEWAY_IP=$(kubectl get -n istio-system service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
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
	pushd tmp/istio-${RELEASE}
	kubectl config use-context "gke_${proj}_${zone}_${CLUSTER_NAME}"
	kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
	PRODUCT_PAGE_IP=$(kubectl get svc productpage -o jsonpath='{.spec.clusterIP}')
	popd
}

function add_vmservice() {
	kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: ServiceEntry
metadata:
  name: vmhttp
spec:
   hosts:
   - vmhttp.default.svc.cluster.local
   ports:
   - number: 8080
     name: http
     protocol: HTTP
   resolution: STATIC
   endpoints:
    - address: 10.128.15.222
      ports:
        http: 8080
EOF
  bin/istioctl  register vmhttp 10.128.15.222 8080
}

function get_verify_info() {
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

if [[ $# -ne 1 ]]; then
  echo "Usage: ./setup.sh cleanup | setup"
  return
fi

case $1 in
  setup)
	   do_all
		 ;;

	cleanup)
	  cleanup
		;;
esac
