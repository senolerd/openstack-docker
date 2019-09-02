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
    ;;
  esac
  }

deploy(){
  stack_list=($(ls -lX $base/branches/$OS_VERSION|grep yml|awk -F' ' '{print $9}'))
  docker network create -d overlay --attachable $OVERLAY_NET_NAME
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
  stack_list=($(ls -lX $base/branches/$OS_VERSION|grep yml|awk -F' ' '{print $9}'))
  for stack in ${stack_list[@]};do
    stack_name=$(echo $stack|awk -F_ '{print $2}')
    echo "-----------"
    #echo stack: $stack
    echo stack_name: $stack_name
    docker -D stack rm OS_$stack_name
    echo "-----------"
    docker network remove $OVERLAY_NET_NAME 2> /dev/null
    done
    }

status(){
    echo -e "\nStack"
    docker stack  ls
    echo -e "\nServices"
    docker service  ls      
  }

 
test(){

     KEYSTONE_PUBLIC_ENDPOINT_TLS=$(echo "$KEYSTONE_PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
         if [ "$KEYSTONE_PUBLIC_ENDPOINT_TLS" == "true" ];then
             PROTO="https"
         else
             PROTO="http"
         fi
    
    if hash openstack 2>/dev/null; then
      openstack image list --os-username admin \
                          --os-password $ADMIN_PASS \
                          --os-user-domain-name default \
                          --os-project-name admin \
                          --os-project-domain-name default \
                          --os-auth-url $PROTO://$DOCKER_HOST_ADDR:$KEYSTONE_PUBLIC_ENDPOINT_PORT/v3 \
                          --os-identity-api-version 3 \
                          --os-cacert $base/branches/$OS_VERSION/etc/ca/intermediate/certs/ca-chain.cert.pem               
    else
      echo -e "\nError: Openstack client isn't found.\n\"python-openstackclient\" would be nice.\n"
    fi
    } 

cacert(){
    clear
    cat $base/branches/$OS_VERSION/etc/ca/intermediate/certs/ca-chain.cert.pem
    cp $base/branches/$OS_VERSION/etc/ca/intermediate/certs/ca-chain.cert.pem $base/
}
case $1 in 
  deploy) set_env;make_pki;deploy;;
  test) set_env;test;;
  cert) set_env;cacert;;
  purge) set_env;purge;;
  status) status;;
  *) echo -e "Usage: deploy | test | cert | purge | status\n"
esac

