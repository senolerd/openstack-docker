#!/bin/bash
start=$(date +%s)
DOCKER_HOST_ADDR=$(echo "$DOCKER_HOST" |awk -F'//' {'print $2'}|awk -F':' {'print $1'})

    yum install -y centos-release-openstack-$OS_VERSION  httpd mod_wsgi mariadb
    yum install -y openstack-glance python-openstackclient
    echo "# INFO: GLANCE package installing done. #"

function create_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $GLANCE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $GLANCE_DB_NAME.* TO '$GLANCE_DB_USER'@'%' IDENTIFIED BY '$GLANCE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $GLANCE_DB_NAME.* TO '$GLANCE_DB_USER'@'localhost' IDENTIFIED BY '$GLANCE_USER_DB_PASS';"
    echo "# INFO: GLANCE DB  Creating is done #"
    }

###############################################################################
###############################################################################

# PERMISSION CHECK
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


###############################################################################
###############################################################################

# GLANCE SETUP

    KEYSTONE_INTERNAL_ENDPOINT_TLS=$(echo "$KEYSTONE_INTERNAL_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    if [ "$KEYSTONE_INTERNAL_ENDPOINT_TLS" == "true" ]
      then KEYSTONE_PROTO="https"
      else KEYSTONE_PROTO="http"
    fi
    echo "#### REMOVE ME: GLANCE KEYSTONE INTERNAL PROTO: $KEYSTONE_PROTO "


    GLANCE_PUBLIC_ENDPOINT_TLS=$(echo "$GLANCE_PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    GLANCE_INTERNAL_ENDPOINT_TLS=$(echo "$GLANCE_INTERNAL_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    GLANCE_ADMIN_ENDPOINT_TLS=$(echo "$GLANCE_ADMIN_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')

    if [ "$GLANCE_PUBLIC_ENDPOINT_TLS" == "true" ]
        then
            echo "########## GLANCE PUBLIC HTTPS INSTALL ##"
            GLANCE_PUB_PROTO="https"
        else
            GLANCE_PUB_PROTO="http"
            echo "########## GLANCE PUBLIC HTTP INSTALL ###"
    fi

    if [ "$GLANCE_INTERNAL_ENDPOINT_TLS" == "true" ]
        then
            echo "########## GLANCE INTERNAL HTTPS INSTALL ##"
            GLANCE_INT_PROTO="https"
        else
            GLANCE_INT_PROTO="http"
            echo "########## GLANCE INTERNAL HTTP INSTALL ###"
    fi


    if [ "$GLANCE_ADMIN_ENDPOINT_TLS" == "true" ]
        then
            echo "########## GLANCE ADMIN HTTPS INSTALL ##"
            GLANCE_ADM_PROTO="https"
        else
            GLANCE_ADM_PROTO="http"
            echo "########## GLANCE ADMIN HTTP INSTALL ###"
    fi

###############################################################################
###############################################################################
    # Take Token
    while true
        do
            if openstack token issue \
                    --os-username admin \
                    --os-password $ADMIN_PASS \
                    --os-user-domain-id default \
                    --os-project-name admin \
                    --os-project-domain-id default \
                    --os-auth-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
                    --os-identity-api-version 3 --insecure
              then
                token=$(openstack token issue \
                    --os-username admin \
                    --os-password $ADMIN_PASS \
                    --os-user-domain-id default \
                    --os-project-name admin \
                    --os-project-domain-id default \
                    --os-auth-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
                    --os-identity-api-version 3 --insecure -f value |head -2)

                echo "##### TOKEN GELMIS OLMALI:  $token ####"
                break
              else
                echo "INFO [Glance]: Waiting to identity server [`date`]"
                sleep 3
            fi
        done


    # openstack project create --domain default --description "Service Project" service
    echo "INFO [Glance]: CHECK SERVICE PROJECT IN CASE"
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              project create --domain default --description "Service Project" service

    # Create service user
    echo "INFO [Glance]: Create service user $GLANCE_SERVICE_USERNAME "
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              user create --domain default --password $GLANCE_SERVICE_USER_PASS $GLANCE_SERVICE_USERNAME

    # Admin role for Glance user in "service" project
    echo "INFO [Glance]: Admin role for Glance user in \"service\" project "
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token"$token" --insecure \
              role add --project service --user $GLANCE_SERVICE_USERNAME admin

    # Glance service creation
    echo "INFO [Glance]: Glance service creation"
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              service create --name glance --description "OpenStack Image" image

    # Glance endpoints
    echo "INFO [Glance]: Glance endpoint creation [admin]"
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              endpoint create --region RegionOne image admin $GLANCE_ADM_PROTO://$KEYSTONE_HOST:$GLANCE_ADMIN_ENDPOINT_PORT

    echo "INFO [Glance]: Glance endpoint creation [internal]"
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              endpoint create --region RegionOne image internal $GLANCE_INT_PROTO://$KEYSTONE_HOST:$GLANCE_INTERNAL_ENDPOINT_PORT

    echo "INFO [Glance]: Glance endpoint creation [public]"
    openstack --os-url $KEYSTONE_PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
              --os-identity-api-version 3 \
              --os-token="$token" --insecure \
              endpoint create --region RegionOne image public $GLANCE_PUB_PROTO://$DOCKER_HOST_ADDR:$GLANCE_PUBLIC_ENDPOINT_PORT


# SET CONFIG FILES

# DB POPULATE

# MAIN

sleep 111d





















function check_permissions(){
    chown -R root:keystone /etc/keystone
    chmod 640 -R  /etc/keystone
    chmod 750 /etc/keystone
    echo "# INFO: PERMISSIONS CHECK IS DONE #"
    }

function keystone_setup(){
    sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
    sed -i "s|^\[token]|[token]\nprovider = fernet\ncaching = true|g" /etc/keystone/keystone.conf
    sed -i "s|^\[cache]|[cache]\nenable = true \nbackend = dogpile.cache.memcached \nbackend_argument = url:$MEMCACHED_HOST:$MEMCACHED_PORT |g" /etc/keystone/keystone.conf
    check_permissions
    mkdir /etc/keystone/fernet-keys
    mkdir /etc/keystone/credential-keys
    chown keystone:keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
    chmod 700 /etc/keystone/fernet-keys /etc/keystone/credential-keys
    ln -s /run/secrets/fernet_0 /etc/keystone/fernet-keys/0
    ln -s /run/secrets/fernet_1 /etc/keystone/fernet-keys/1
    ln -s /run/secrets/credential_0 /etc/keystone/credential-keys/0
    ln -s /run/secrets/credential_1 /etc/keystone/credential-keys/1
    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
    }

function populate_keystone(){
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    keystone-manage bootstrap --bootstrap-password adminpass \
    --bootstrap-public-url $KEYSTONE_PUBLIC_ENDPOINT \
    --bootstrap-internal-url $KEYSTONE_INTERNAL_ENDPOINT \
    --bootstrap-region-id $KEYSTONE_REGION
  }

function install_first_node(){
    create_keystone_db
    keystone_setup
    populate_keystone
    }

function add_new_node(){
    keystone_setup
    }

function main(){
    while true
        do
          if  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e 'quit' ; then
                echo "# INFO: SQL connected. $(date)"
                if  mysql -u $KEYSTONE_DB_USER -h $MYSQL_HOST -p$KEYSTONE_USER_DB_PASS -e 'quit' 2> /dev/null ; then
                  echo "# INFO: Installing additional api node."
                  add_new_node
                else
                  echo "# INFO: Installing new api node node ."
                  install_first_node
                fi
                break
          else
                echo "# INFO: Waiting for SQL server up.. Last trying time: $(date)"
                sleep 1
          fi
        done
    end=$(date +%s)
    echo "# INFO: $OS_VERSION installing report: (started: $start, ended: $end, took $(expr $end - $start) secs )"
    httpd -DFOREGROUND
    }

main






