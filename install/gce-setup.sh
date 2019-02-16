export GATEWAY_IP="${GATEWAY_IP:-35.238.212.236}"
export SERVICE_HOST="${SERVICE_HOST-productpage.default.svc.cluster.local}"
export SERVICE_IP="${SERVICE_IP-10.51.248.227}"

# This script is supposed to run on a GCE instance.
function setup() {
  # if [[ -z "${GATEWAY_IP}"]]
  # then
  #   echo "Please set GATEWAY_IP"
  #   return
  # fi
  # for f in "root-cert.pe" "" ""; do
  #   if [[ ! -f $f ]]; then
  #     echo "Ensure file exists, $f"
  #   fi
  # done
  # Clean up first.
  # sudo su
  stop_workload
  curl https://storage.googleapis.com/istio-release/releases/1.1.0-snapshot.6/deb/istio-sidecar.deb  -L > istio-sidecar.deb
  dpkg -i istio-sidecar.deb
  echo "$GATEWAY_IP istio-citadel istio-pilot istio-pilot.istio-system" >> /etc/hosts
  mkdir -p /etc/certs
  cp {root-cert.pem,cert-chain.pem,key.pem} /etc/certs
  cp cluster.env /var/lib/istio/envoy
  systemctl start istio
  systemctl start istio-auth-node-agent
  # Then kill this...
  # node_agent
}

# echo "$PRODUCT_PAGE_IP productpage.default.svc.cluster.local" >> /etc/hosts
function add_kube_service() {
  if [[ -z "${SERVICE_HOST}" || -z "${SERVICE_IP}" ]]; then
    echo "Empty SERVICE_HOST or SERVICE_IP, please set."
    return
  fi
  echo "Add service from kubernetes clusters to the VM, Host ${SERVICE_HOST} ${SERVICE_IP}"
  sudo echo "${SERVICE_IP} ${SERVICE_HOST}" >> /etc/hosts
}

function stop_workload() {
  sudo systemctl stop istio
  sudo systemctl stop istio-auth-node-agent
  sudo sed -i  '/istio\|cluster.local/d' /etc/hosts
}

# TODO: not tested yet.
function start_helloworld() {
  kill $(ps aux | grep 'SimpleHTTPServer' | awk '{print $2}')
  python -m SimpleHTTPServer 8080 > http-server.output 2>&1 &
}

function echo_env() {
  echo "env is " $ECHO_ENV
}

# Usage:
# - Deploy the GCE VM first.
# - Setup Istio sidecar and node agent on the VM first, `sudo bash ./gce-setup.sh  setup`
# - Add a Kubernete service in to /etc/hosts for resolution: `sudo bash ./gce-setup.sh  addservice`
# - Clean up the VM environment, `sudo bash ./gce-setup.sh cleanup`
# Status: clean up is not tested, first several works, may not be in a clean state
# TODO: remove all hardcoded environment variable, and make them configurable.
echo_env

case $1 in
  setup)
    setup
     ;;

  addservice)
    add_kube_service
    ;;

	cleanup)
    cleanup
    ;;

esac
