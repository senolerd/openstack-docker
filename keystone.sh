#!/bin/bash
start=$(date +%s)
DOCKER_HOST_ADDR=$(echo "$DOCKER_HOST" |awk -F'//' {'print $2'}|awk -F':' {'print $1'})

echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "
echo "####### DOCKER HOST: $DOCKER_HOST_ADDR ########### "

    yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb
    yum install -y openstack-keystone
#    yum install -y openstack-keystone python-openstackclient
    yum clean all
    echo "# INFO: PACKAGE INSTALLING IS DONE #"

function create_keystone_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    echo "# INFO: DB CREATING IS DONE #"
    }

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
    }

function populate_keystone(){
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    PUBLIC_ENDPOINT_TLS=$(echo "$PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')

    if [ "$PUBLIC_ENDPOINT_TLS" == "true" ]
      then
        PROTO=https
      else PROTO=http
        ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
    sed -i "s|^Listen 5000|Listen 5000\n ServerName $DOCKER_HOST_ADDR|g" /etc/keystone/keystone.conf

    fi

    keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
    --bootstrap-public-url $PROTO://$DOCKER_HOST_ADDR:$PUBLIC_ENDPOINT_PORT/$PUBLIC_ENDPOINT_VERSION \
    --bootstrap-internal-url http://$KEYSTONE_HOST:$INTERNAL_ENDPOINT_PORT/$INTERNAL_ENDPOINT_VERSION \
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






