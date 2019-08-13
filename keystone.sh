#!/bin/bash
echo "#########################################"
echo "#######    INSTALLING STARTED     #######"
echo "#########################################"



start=$(date +%s)
DOCKER_HOST_ADDR=$(echo "$DOCKER_HOST" |awk -F'//' {'print $2'}|awk -F':' {'print $1'})

    yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb > /dev/null
    yum install -y openstack-keystone mod_ssl > /dev/null
#    yum install -y openstack-keystone python-openstackclient
    yum clean all
    echo "# INFO: Package installing is done. #"

function create_keystone_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    echo "# INFO: DB creating is done. #"
    }

function check_permissions(){
    chown -R root:keystone /etc/keystone
    echo "ls -al /etc/|grep keystone"
    ls -al /etc/|grep keystone

    echo "--------------------------"
    echo "ls -al /etc/keystone"
    ls -al /etc/keystone

    echo "--------------------------"
    echo "ls -al /etc/keystone/tls"
    ls -al /etc/keystone/tls



    chmod 0640 -R /etc/keystone
    chmod 0750 /etc/keystone

    chmod -R 0640 /etc/keystone/tls/*
    echo "# INFO: Permission check is done ? #"
    }

function keystone_setup(){
    sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
    sed -i "s|^\[token]|[token]\nprovider = fernet\ncaching = true|g" /etc/keystone/keystone.conf
    sed -i "s|^\[cache]|[cache]\nenable = true \nbackend = dogpile.cache.memcached \nbackend_argument = url:$MEMCACHED_HOST:$MEMCACHED_PORT |g" /etc/keystone/keystone.conf
    mkdir /etc/keystone/fernet-keys
    mkdir /etc/keystone/credential-keys
    chown keystone:keystone /etc/keystone/fernet-keys /etc/keystone/credential-keys
    chmod 700 /etc/keystone/fernet-keys /etc/keystone/credential-keys
    ln -s /run/secrets/fernet_0 /etc/keystone/fernet-keys/0
    ln -s /run/secrets/fernet_1 /etc/keystone/fernet-keys/1
    ln -s /run/secrets/credential_0 /etc/keystone/credential-keys/0
    ln -s /run/secrets/credential_1 /etc/keystone/credential-keys/1

#    ln -s /run/secrets/10.0.0.71.crt /etc/keystone/10.0.0.71.crt
#    ln -s /run/secrets/10.0.0.71.key /etc/keystone/10.0.0.71.key

    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/

    sed -i "s|Listen 5000|Listen 5000\nServerName $DOCKER_HOST_ADDR|g" /etc/httpd/conf.d/wsgi-keystone.conf


    PUBLIC_ENDPOINT_TLS=$(echo "$PUBLIC_ENDPOINT_TLS" | tr '[:upper:]' '[:lower:]')
    if [ "$PUBLIC_ENDPOINT_TLS" == "true" ]
        then
            echo "#########################################"
            echo "########## HTTPS INSTALL     ############"
            echo "#########################################"

            PROTO="https"
            mkdir /etc/keystone/tls
            tls_dir="/etc/keystone/tls"
            sed -i "s|5000>|$PUBLIC_ENDPOINT_PORT>\n\tSSLEngine on\n\tSSLCertificateFile $tls_dir/server.crt\n\tSSLCertificateKeyFile $tls_dir/server.key\n |g" /etc/httpd/conf.d/wsgi-keystone.conf

            echo "
            [req]
            distinguished_name = req_distinguished_name
            x509_extensions = v3_req
            prompt = no
            [req_distinguished_name]
            C = US
            ST = NY
            L = New Dork City
            O = Snake Oil Inc.
            OU = Kelly's nook
            CN = 10.0.0.71
            [v3_req]
            keyUsage = keyEncipherment, dataEncipherment
            extendedKeyUsage = serverAuth
            subjectAltName = @alt_names

            [alt_names]
            IP.1 = 10.0.0.71
            IP.2 = 10.0.0.72
            IP.3 = 10.0.0.73
            " > $tls_dir/os.cnf

            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -config $tls_dir/os.cnf -keyout $tls_dir/server.key -out $tls_dir/server.crt
            echo "####### ls $tls_dir #######"
            ls -al $tls_dir
            echo "####### cat  $tls_dir/os.cnf #######"
            cat $tls_dir/os.cnf



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
    --bootstrap-public-url $PROTO://$DOCKER_HOST_ADDR:$PUBLIC_ENDPOINT_PORT/$PUBLIC_ENDPOINT_VERSION \
    --bootstrap-internal-url $PROTO://$KEYSTONE_HOST:$INTERNAL_ENDPOINT_PORT/$INTERNAL_ENDPOINT_VERSION \
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

    check_permissions
    echo "# INFO: $OS_VERSION installing report: (started: $start, ended: $end, took $(expr $end - $start) secs )"

    httpd -DFOREGROUND
    echo "------------------------------------"
    cat /var/log/keystone/*

    echo "------------------------------------"
    cat /var/log/httpd/*


    }

main






