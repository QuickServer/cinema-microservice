#!/bin/bash

# default parameters1
DRIVER="google"
MANAGERS=3
WORKERS=3
DISK_SIZE="20000"
MEMORY="2048"
DOCKER_VERSION="https://github.com/boot2docker/boot2docker/releases/download/v1.13.0/boot2docker.iso"
GOOGLE_PROJECT_ID="cool-discipline-161613"
GOOGLE_ZONE="us-central1-c"
GOOGLE_MACHINE_TYPE="g1-small"
GOOGLE_MACHINE_IMAGE="https://www.googleapis.com/compute/v1/projects/ubuntu-os-cloud/global/images/family/ubuntu-1604-lts"
GOOGLE_TAGS="http-server,https-server"
ADDITIONAL_PARAMS=

function usage {
  echo "Usage: bash $0  [OPTIONS]

Run a command in a new container

Options:
  -d, --driver                     virtual machine provider or cloud provider (default virtualbox)
  -m, --manager                    number of managers to create (default 1)
  -w, --worker                     number of workers to create (default 2)
  -v, --version                    boot2docker github url (default version 1.13.0)
  -ds, --disksize                  hard disk size for docker-machine (default 20GB)
  -r, --memory                     memory ram size for docker-machine (default 2GB)"
  exit 1
}

# get parameters
while [ "$#" -gt 0 ]; do
  case "$1" in
    --driver|-d)
    DRIVER="$2"
    shift 2
  	;;
    --manager|-m)
    MANAGERS="$2"
    shift 2
    ;;
    --worker|-w)
    WORKERS="$2"
    shift 2
    ;;
    --version|-v)
    DOCKER_VERSION="$2"
    shift 2
    ;;
    --disksize|-ds)
    DISK_SIZE="$2"
    shift 2
    ;;
    --memory|-r)
    MEMORY="$2"
	shift 2
    ;;
    -h|--help)
    usage
    ;;
  esac
done

if [ "$DRIVER" == "virtualbox" ]; then
  echo "-> about to create a swarm with $MANAGERS manager(s) and $WORKERS WORKERS on $DRIVER machines"
  ADDITIONAL_PARAMS="--virtualbox-disk-size ${DISK_SIZE} --virtualbox-memory ${MEMORY} --virtualbox-boot2docker-url=${DOCKER_VERSION}"
fi

if [ "$DRIVER" == "google" ]; then
  echo "-> about to create a swarm with $MANAGERS manager(s) and $WORKERS WORKERS on $DRIVER machines"
  ADDITIONAL_PARAMS=" --google-project ${GOOGLE_PROJECT_ID} --google-zone ${GOOGLE_ZONE} --google-machine-image ${GOOGLE_MACHINE_IMAGE} --google-tags=${GOOGLE_TAGS} --google-machine-type ${GOOGLE_MACHINE_TYPE}"
fi

function getIP {
  echo $(docker-machine ip $1)
}

function get_worker_token {
  echo $(docker-machine ssh manager1 docker swarm join-token worker -q)
}

function get_manager_token {
  echo $(docker-machine ssh manager1 docker swarm join-token manager -q)
}

function createManagerNode {
  # create manager machines
  for i in $(seq 1 $MANAGERS);
  do
    echo "== Creating manager$i machine ...";
    docker-machine create -d $DRIVER $ADDITIONAL_PARAMS manager$i
  done
}

function createWorkerNode {
  # create worker machines
  for i in $(seq 1 $WORKERS);
  do
    echo "== Creating worker$i machine ...";
    docker-machine create -d $DRIVER $ADDITIONAL_PARAMS worker$i
  done
}

function initSwarmManager {
  # initialize swarm mode and create a manager
  echo '============================================'
  echo "======> Initializing first swarm manager ..."
  echo "======> Adding current user to docker group..."
  docker-machine ssh manager1 sudo usermod -aG docker docker-user
  echo "======> Removing existing swarm state, if any..."
  docker-machine ssh manager1 docker swarm leave --force
  echo "======> Adding first swarm manager..."
  docker-machine ssh manager1 docker swarm init --advertise-addr $(getIP manager1)
}

function join_node_swarm_as_worker {
  # WORKERS join swarm
  for node in $(seq 1 $WORKERS);
  do
    echo "======> Adding docker-user to docker group..."
    docker-machine ssh worker$node sudo usermod -aG docker docker-user
    echo "======> Removing existing swarm state, if any..."
    docker-machine ssh worker$node docker swarm leave --force
    echo "======> worker$node joining swarm as worker ..."
    docker-machine ssh worker$node docker swarm join --token $(get_worker_token) $(getIP manager1):2377
  done
}

function join_node_swarm_as_manager {
  # WORKERS join swarm
  for node in $(seq 2 $MANAGERS);
  do
    echo "======> Adding docker- user to docker group..."
    docker-machine ssh manager$node sudo usermod -aG docker docker-user
    echo "======> Removing existing swarm state, if any..."
    docker-machine ssh manager$node docker swarm leave --force
    echo "======> worker$node joining swarm as worker ..."
    docker-machine ssh manager$node docker swarm join --token $(get_manager_token) $(getIP manager1):2377
  done
}

# Display status
function status {
  echo "-> list swarm nodes"
  docker-machine ssh manager1 docker node ls
  echo
  echo "-> list machines"
  docker-machine ls
}

# Start RancherOS
function startRancherOS {
  echo "-> Starting RancherOS to monitor the cluster"
  docker-machine ssh manager1 docker run --name rancher --restart=unless-stopped -p 9000:8080 -d rancher/server
}

function main {
  createManagerNode
  createWorkerNode
  initSwarmManager
  join_node_swarm_as_manager
  join_node_swarm_as_worker
  status
 # startRancherOS
}

function reset {
  docker-machine rm manager1 worker1 worker2 -y
}

#reset
main
