#!/bin/bash
echo "--------------------------------------------------------"
export base=$(pwd)
export $(cat openstack.env |grep -v "#")
export DOCKER_HOST_ADDR=$(docker info|grep "Manager Addresses" -A 1|tail -1|awk -F: {'print $1'}|awk -F" " '{print $1}')
echo "--------------------------------------------------------"


INSECURE=$(echo "$INSECURE" | tr '[:upper:]' '[:lower:]')
case $INSECURE in
false)
 echo "!! INSECURE is false in the env file, i'm not ready for that for now !!";exit;;
esac

branches/rocky/etc/create_cert.sh
docker network create -d overlay --attachable $OVERLAY_NET_NAME



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

deploy
echo $DOCKER_HOST_ADDR
echo "--- EoF ---"
