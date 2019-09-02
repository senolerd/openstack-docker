#!/bin/bash
started=$(date +%s)

    yum install -y centos-release-openstack-$OS_VERSION  httpd mod_wsgi mariadb
    yum install -y openstack-glance python-openstackclient
    echo "# INFO: GLANCE package installing done. #"

    KEYSTONE_INTERNAL_ENDPOINT_TLS=$(echo "$KEYSTONE_INTERNAL_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    if [ "$KEYSTONE_INTERNAL_ENDPOINT_TLS" == "true" ]
      then 
        KEYSTONE_PROTO="https";
        cert="cafile = /etc/glance/ca_chain.pem"
      else KEYSTONE_PROTO="http"
    fi

function create_db(){
    echo "create_db started"

    while true
      do
        if mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "use $GLANCE_DB_NAME;" ;
          then
            echo "INFO: GLANCE DB exist, heading to server configuration."
            break
          else
            mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $GLANCE_DB_NAME;"
            mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $GLANCE_DB_NAME.* TO '$GLANCE_DB_USER'@'%' IDENTIFIED BY '$GLANCE_USER_DB_PASS';"
            mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $GLANCE_DB_NAME.* TO '$GLANCE_DB_USER'@'localhost' IDENTIFIED BY '$GLANCE_USER_DB_PASS';"
            su -s /bin/sh -c "glance-manage db_sync" glance
            echo "# INFO: GLANCE DB creating and populating is done. #"
            break
        fi
      done
    echo "create_db ended"

   }


function check_permissions(){
# https://docs.openstack.org/security-guide/identity/checklist.html

    chown -R keystone:keystone /etc/keystone

    echo "\nINFO: GLANCE All directories to be set 750"
    for directory in $(find /etc/glance/ -type d) ; do
        chmod 0750 $directory
        echo $(stat -L -c "%a" $directory), Ownership: $(stat -L -c "%U %G" $directory | egrep "glance glance") " :: $directory"
      done

    echo "\nINFO: GLANCE All files to be set 640"
    for file in $(find /etc/glance/ -type f) ; do
        chmod 0640 $file
        echo $(stat -L -c "%a" $file), Ownership: $(stat -L -c "%U %G" $file | egrep "glance glance") " :: $file "
      done

    echo "# INFO: GLANCE Permission check is done. #"
    }


function take_token(){
    echo "take_token started"

    INSECURE=$(echo "$INSECURE" | tr '[:upper:]' '[:lower:]')
    if [ "$INSECURE" == "true" ] ; then CERT_CHK=" --insecure ";fi

    token=$(openstack token issue \
                      --os-username admin \
                      --os-password $ADMIN_PASS \
                      --os-user-domain-id default \
                      --os-project-name admin \
                      --os-project-domain-id default \
                      --os-auth-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
                      --os-identity-api-version 3 $CERT_CHK -f value|grep gAAA)

     OS_ARGS="--os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
                --os-identity-api-version 3 --os-token=$token $CERT_CHK"

    echo "take_token ended"

}


function glance_api_setup(){
    echo "glance_api_setup started"
    echo "#### REMOVE ME: GLANCE KEYSTONE INTERNAL PROTO: $KEYSTONE_PROTO "
    export glance_cert=""
    GLANCE_PUBLIC_ENDPOINT_TLS=$(echo "$GLANCE_PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    GLANCE_INTERNAL_ENDPOINT_TLS=$(echo "$GLANCE_INTERNAL_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    GLANCE_ADMIN_ENDPOINT_TLS=$(echo "$GLANCE_ADMIN_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')

    if [ "$GLANCE_PUBLIC_ENDPOINT_TLS" == "true" ]
        then 
             GLANCE_PUB_PROTO="https"
             glance_cert="ca_file=\n/etc/glance/ca_chain.pem \ncert_file=/etc/glance/tls/server_key.pem \nkey_file=/etc/glance/tls/server_crt.pem" 
        else 
             GLANCE_PUB_PROTO="http"
    fi

    if [ "$GLANCE_INTERNAL_ENDPOINT_TLS" == "true" ]
        then 
             GLANCE_INT_PROTO="https"
        else 
             GLANCE_INT_PROTO="http"
    fi


    if [ "$GLANCE_ADMIN_ENDPOINT_TLS" == "true" ]
        then 
             GLANCE_ADM_PROTO="https"
        else 
             GLANCE_ADM_PROTO="http"
    fi

    while true
        do
            if take_token
              then
                echo "##### Remove Me: TOKEN:  $token ####"
                break
              else
                echo "INFO [Glance]: Waiting to identity server [`date`]"
                sleep 5
            fi
        done


    # openstack project create --domain default --description "Service Project" service
    echo "INFO [Glance]: CHECK SERVICE PROJECT IN CASE"
    if openstack project show service --domain default $OS_ARGS > /dev/null 2>&1
      then echo "'service' project is exist"
      else openstack project create --domain default --description "Service Project" service $OS_ARGS
    fi


    # Create service user
    echo "INFO [Glance]: Create service user glance user name"
    if openstack user show $GLANCE_SERVICE_USERNAME $OS_ARGS > /dev/null 2>&1
      then echo "$GLANCE_SERVICE_USERNAME is exist"
      else openstack user create --domain default --password $GLANCE_SERVICE_USER_PASS $GLANCE_SERVICE_USERNAME $OS_ARGS
    fi

    # Admin role for Glance user in "service" project
    echo "INFO [Glance]: Admin role for Glance user in 'service' project "
    openstack role add --project service --user $GLANCE_SERVICE_USERNAME admin $OS_ARGS

    # Glance service creation
    echo "INFO [Glance]: Glance service creation"
    if openstack service show glance $OS_ARGS > /dev/null 2>&1
      then echo "'glance' service exist."
      else openstack service create --name glance --description "OpenStack Image" image  $OS_ARGS
    fi

    # Glance endpoints (probably only public is going to be fine soon)
    if openstack endpoint list --service glance --interface public /dev/null 2>&1
      then echo "'glance' public endpoint exist." 
      else openstack endpoint create --region $REGION image public $GLANCE_PUB_PROTO://$DOCKER_HOST_ADDR:$GLANCE_PUBLIC_ENDPOINT_PORT $OS_ARGS
    fi

    if openstack endpoint list --service glance --interface internal /dev/null 2>&1
      then echo "'glance' internal endpoint exist."
      else openstack endpoint create --region $REGION image internal $GLANCE_INT_PROTO://$DOCKER_HOST_ADDR:$GLANCE_INTERNAL_ENDPOINT_PORT $OS_ARGS
    fi

    if openstack endpoint list --service glance --interface admin /dev/null 2>&1
      then echo "'glance' public endpoint exist."
      else openstack endpoint create --region $REGION image admin $GLANCE_ADM_PROTO://$DOCKER_HOST_ADDR:$GLANCE_ADMIN_ENDPOINT_PORT $OS_ARGS
    fi

    # Token revoke
    openstack token revoke "$token" $OS_ARGS
    echo "glance_api_setup ended"

}




# SET CONFIG FILES
function server_configuration(){
    cert=""
    if [ "$KEYSTONE_PROTO" == "https" ]
       then cert="cafile = /etc/glance/ca_chain.pem"
    fi

    echo "server_configuration started"
    keystone_authtoken="\
    \n[keystone_authtoken] \
    \nauth_url = $KEYSTONE_PROTO://$DOCKER_HOST_ADDR:$KEYSTONE_INTERNAL_ENDPOINT_PORT \
    \nmemcached_servers = $MEMCACHED_HOST:$MEMCACHED_PORT \
    \nauth_type = password \
    \nproject_domain_name = Default \
    \nuser_domain_name = Default \
    \nproject_name = service \
    \nusername = $GLANCE_SERVICE_USERNAME \
    \npassword = $GLANCE_SERVICE_USER_PASS \
    \n$cert \
    "
    glance_store="\
    \n[glance_store] \
    \nstores = file,http \
    \ndefault_store = file \
    \nfilesystem_store_datadir = /var/lib/glance/images/ \
    "

    for conf_file in /etc/glance/glance-api.conf /etc/glance/glance-registry.conf ;
      do
        sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$GLANCE_DB_USER:$GLANCE_USER_DB_PASS@$MYSQL_HOST/$GLANCE_DB_NAME|g" $conf_file
        sed -i "s|^\[keystone_authtoken]|$keystone_authtoken|g" $conf_file
        sed -i "s|^\[paste_deploy]|[paste_deploy]\nflavor = keystone\n|g" $conf_file
        sed -i "s|^\[DEFAULT]|[DEFAULT]$glance_cert|g" $conf_file
      done

    sed -i "s|^\[glance_store]|$glance_store|g" /etc/glance/glance-api.conf
    echo "server_configuration ended"
}


# DB POPULATE

# MAIN
glance_api_setup
server_configuration
create_db

end=$(date +%s)
echo "# INFO: GLANCE $OS_VERSION installing report: (started: $start, ended: $end, took $(expr $end - $started) secs )"
glance-control api start

sleep 1111d




