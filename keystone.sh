#!/bin/bash
start=$(date +%s)
echo "###################################################"
echo "#######  KEYSTONE INSTALLING STARTED $start"
echo "###################################################"

DOCKER_HOST_ADDR=$(echo "$DOCKER_HOST" |awk -F'//' {'print $2'}|awk -F':' {'print $1'})

    yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb
    yum install -y openstack-keystone mod_ssl
    echo "# INFO: KEYSTONE Package installing is done. #"

function create_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    echo "# INFO: KEYSTONE DB creating is done. #"
    }

function check_permissions(){
# https://docs.openstack.org/security-guide/identity/checklist.html

    chown -R keystone:keystone /etc/keystone
    echo "# Permission Check Report #"
    echo "INFO: All directories to be set 750"
    for directory in $(find /etc/keystone/ -type d) ; do
        chmod 0750 $directory
        echo $(stat -L -c "%a" $directory), Ownership: $(stat -L -c "%U %G" $directory | egrep "keystone keystone") " :: $directory"
      done

    echo "INFO: All files to be set 640"
    for file in $(find /etc/keystone/ -type f) ; do
        chmod 0640 $file
        echo $(stat -L -c "%a" $file), Ownership: $(stat -L -c "%U %G" $file | egrep "keystone keystone") " :: $file "
      done

    echo "# INFO: Permission check is done ? #"
    }

function keystone_setup(){
    mkdir /etc/keystone/fernet-keys
    mkdir /etc/keystone/credential-keys

    sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
    sed -i "s|^\[token]|[token]\nprovider = fernet\ncaching = true|g" /etc/keystone/keystone.conf
    sed -i "s|^\[cache]|[cache]\nenable = true \nbackend = dogpile.cache.memcached \nbackend_argument = url:$MEMCACHED_HOST:$MEMCACHED_PORT |g" /etc/keystone/keystone.conf

    chown keystone:keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
    chmod 700 /etc/keystone/fernet-keys /etc/keystone/credential-keys
    ln -s /run/secrets/fernet_0 /etc/keystone/fernet-keys/0
    ln -s /run/secrets/fernet_1 /etc/keystone/fernet-keys/1
    ln -s /run/secrets/credential_0 /etc/keystone/credential-keys/0
    ln -s /run/secrets/credential_1 /etc/keystone/credential-keys/1
    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
    sed -i "s|Listen 5000|Listen 5000\nServerName $DOCKER_HOST_ADDR|g" /etc/httpd/conf.d/wsgi-keystone.conf


    KEYSTONE_PUBLIC_ENDPOINT_TLS=$(echo "$KEYSTONE_PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    if [ "$KEYSTONE_PUBLIC_ENDPOINT_TLS" == "true" ]
        then
            echo "#########################################"
            echo "########## HTTPS INSTALL     ############"
            echo "#########################################"
            PROTO="https"
            tls_dir="/etc/keystone/tls"
            mkdir $tls_dir
            ln -s /run/secrets/server.key $tls_dir/server.key
            ln -s /run/secrets/server.crt $tls_dir/server.crt
            sed -i "s|5000>|$KEYSTONE_PUBLIC_ENDPOINT_PORT>\n\tSSLEngine on\n\tSSLCertificateFile $tls_dir/server.crt\n\tSSLCertificateKeyFile $tls_dir/server.key\n |g" /etc/httpd/conf.d/wsgi-keystone.conf
        else
            PROTO="http"
            echo "#########################################"
            echo "########## HTTP INSTALL      ############"
            echo "#########################################"
    fi
    }

function populate_keystone(){
    su -s /bin/sh -c "keystone-manage db_sync" keystone

    keystone-manage bootstrap --bootstrap-password $ADMIN_PASS \
    --bootstrap-public-url $PROTO://$DOCKER_HOST_ADDR:$KEYSTONE_PUBLIC_ENDPOINT_PORT/$KEYSTONE_PUBLIC_ENDPOINT_VERSION \
    --bootstrap-internal-url $PROTO://$KEYSTONE_HOST:$KEYSTONE_INTERNAL_ENDPOINT_PORT/$KEYSTONE_INTERNAL_ENDPOINT_VERSION \
    --bootstrap-region-id $REGION
  }

function install_first_node(){
    create_db
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

    check_permissions
    echo "# INFO: $OS_VERSION installing report: (started: $start, ended: $end, took $(expr $end - $start) secs )"
    httpd -DFOREGROUND


    }

main






