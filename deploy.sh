#!/bin/bash
export base=$(pwd)

set_env(){

  for line_no in $(seq 1 $(grep '^[A-Z]' openstack.env|wc -l))
    do
     line_content=$(grep '^[A-Z]' openstack.env|head -$line_no|tail -1)
     variable=$(echo $line_content|awk -F= {'print $1'})
     value=$(echo $line_content|awk -F= {'print $2'})
     export $variable="$value"
    done
    export DOCKER_HOST_ADDR=$(docker info|grep "Manager Addresses" -A 1|tail -1|awk -F: {'print $1'}|awk -F" " '{print $1}')
  }


make_pki(){
  target_host=$(docker node ls --format "{{.Hostname}}:{{.ManagerStatus}}"|grep Leader|awk -F: {'print $1'})
  export target_host=$target_host
  INSECURE=$(echo "$INSECURE" | tr '[:upper:]' '[:lower:]')
  case $INSECURE in
  false)
    echo "!! INSECURE is false in the env file, No TLS for ya";exit
    ;;
  true)
    echo "TLS is being done"
    $base/branches/$OS_VERSION/etc/create_cert.sh
    cd $base/branches/$OS_VERSION/etc/
    . create_cert.sh $DOCKER_HOST_ADDR
    ;;
  esac
  }

network(){
  docker network create -d overlay --attachable $OVERLAY_NET_NAME
  }

deploy(){
  stack_list=($(ls -lX $base/branches/rocky|grep yml|awk -F' ' '{print $9}'))

  for stack in ${stack_list[@]};do
    stack_name=$(echo $stack|awk -F_ '{print $2}')
    echo "-----------"
    echo stack: $stack
    echo stack_name: $stack_name
    docker -D stack deploy -c $base/branches/$OS_VERSION/$stack OS_$stack_name
    echo "-----------"
    done
    }

purge(){
  stack_list=($(ls -lX $base/branches/rocky|grep yml|awk -F' ' '{print $9}'))

  for stack in ${stack_list[@]};do
    stack_name=$(echo $stack|awk -F_ '{print $2}')
    echo "-----------"
    echo stack: $stack
    echo stack_name: $stack_name
    docker -D stack rm -c $base/branches/$OS_VERSION/$stack OS_$stack_name
    echo "-----------"
    done
    }

pipeline(){
  set_env
  make_pki
  network
  deploy
}

pipeline
echo "--- EoDeployment ---"
echo "$DOCKER_HOST_ADDR"
