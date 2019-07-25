i#!/bin/bash
# this line will be removed
start=$(date +%s)

function package_installing(){
  yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient
  yum clean packages
  echo "# PACKAGE INSTALLING IS DONE     #"
  }


function openstackclient_pipeline(){
  package_installing

  while true
    do
      if [ ryans_token=$(openstack token issue -f value  --os-auth-url $KEYSTONE_INTERNAL_ENDPOINT \
       --os-identity-api-version 3 --os-project-domain-name Default --os-user-domain-name Default \
       --os-project-name admin --os-password $ADMIN_PASS --os-username admin|grep '^gAAA') ] ; then
          
        alias openstack="--os-token $ryans_token --os-url $KEYSTONE_PUBLIC_ENDPOINT"
        openstack domain create --description "An Example Domain" example
        openstack project create --domain default --description "Service Project" service 
        openstack project create --domain default --description "Demo Project" myproject
        openstack user create --domain default --password myuserpass myuser
        openstack role create myrole
        openstack role add --project myproject --user myuser myrole
        break
      else
        echo "Waiting for api server (Last tried: $(date))"
        sleep 1
      fi
    done

  echo "
  export OS_USERNAME=admin
  export OS_PASSWORD=$ADMIN_PASS
  export OS_PROJECT_NAME=admin
  export OS_USER_DOMAIN_NAME=Default
  export OS_PROJECT_DOMAIN_NAME=Default
  export OS_AUTH_URL=$KEYSTONE_INTERNAL_ENDPOINT
  export OS_IDENTITY_API_VERSION=3
  " > /admin-rc


  end=$(date +%s)
  echo "EoF ## (started: $start, ended: $end, took $(expr $end - $start) secs   )  ## "
  sleep 666d
  }


openstackclient_pipeline
