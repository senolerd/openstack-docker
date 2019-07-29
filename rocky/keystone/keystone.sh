#!/bin/bash
start=$(date +%s)

    yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb
    yum install -y openstack-keystone python-openstackclient
    yum clean all
    echo "# PACKAGE INSTALLING IS DONE #"

# Start the stark with single api, then add. Additional nodes must check current installation and shouldn't push db sync
# * after the installation, mysql client should check the keystone db, then has to take its own way.


function create_keystone_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    echo "# DB CREATING IS DONE #"
    }

function check_permissions(){
    chown -R root:keystone /etc/keystone
    chmod 640 -R  /etc/keystone
    chmod 750 /etc/keystone
    }

function keystone_setup(){
    # Edit keystone.conf
    sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
    sed -i "s|^\[token]|[token]\nprovider = fernet|g" /etc/keystone/keystone.conf
    check_permissions
    keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
    keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
    ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
    }

function populate_keystone(){
    # Populate keystone db structure
    su -s /bin/sh -c "keystone-manage db_sync" keystone
    keystone-manage bootstrap --bootstrap-password adminpass \
    --bootstrap-public-url $KEYSTONE_PUBLIC_ENDPOINT \
    --bootstrap-internal-url $KEYSTONE_INTERNAL_ENDPOINT \
    --bootstrap-region-id $KEYSTONE_REGION
    ryans_token=$(openstack token issue -f value  --os-auth-url $KEYSTONE_INTERNAL_ENDPOINT --os-identity-api-version 3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-password $ADMIN_PASS --os-username admin|grep '^gAAA')
    openstack project create service --domain default --description "Service Project" --os-token $ryans_token --os-url $KEYSTONE_PUBLIC_ENDPOINT
  }


function install_first_node(){
    create_keystone_db
    keystone_setup
    populate_keystone
    }

function install_additional_node(){
    keystone_setup
    }

function sql_connection_check(){
    while true
      do
        if  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e 'quit' ; then
          echo "SQL connected. $(date)"
          if  mysql -u $KEYSTONE_DB_USER -h $MYSQL_HOST -p$KEYSTONE_USER_DB_PASS -e 'quit' ; then
            echo "Installing additional api node."
            install_additional_node
          else:
            echo "New api node node installing."
            install_first_node
          break
        else
          echo "Waiting for SQL server up.. Last trying time: $(date)"
          sleep 1
        fi
      done
    }


end=$(date +%s)
echo "EoF for $OS_VERSION installing report. (started: $start, ended: $end, took $(expr $end - $start) secs   )"

httpd -DFOREGROUND



