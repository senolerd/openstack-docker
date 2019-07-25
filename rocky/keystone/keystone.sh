i#!/bin/bash
# this line will be removed
start=$(date +%s)

function package_installing(){
  yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb 
  yum install -y openstack-keystone python-openstackclient
  yum clean packages
  echo "# PACKAGE INSTALLING IS DONE     #"
}


function create_keystone_db(){
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  echo "# DB CREATING IS DONE     #"
  }

function sql(){
  while true
    do
      if  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e 'quit' ; then
        create_keystone_db 
        break
      else
        echo "Waiting for SQL server up.. Last trying time: $(date)"
        sleep 1
      fi
    done
  }


function check_permissions(){
  chown -R root:keystone /etc/keystone
  chmod 640 -R root:keystone /etc/keystone
  chmod 750  root:keystone /etc/keystone
}


function keystone_setup(){
  # Edit keystone.conf 
  sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
  sed -i "s|^\[token]|[token]\nprovider = fernet|g" /etc/keystone/keystone.conf

  # Populate keystone db structure
  su -s /bin/sh -c "keystone-manage db_sync" keystone

  check_permissions

  # Create Fernet keys
  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

  # Create keystone's public endpoint
  keystone-manage bootstrap --bootstrap-password adminpass \
  --bootstrap-public-url $KEYSTONE_PUBLIC_ENDPOINT \
  --bootstrap-internal-url $KEYSTONE_INTERNAL_ENDPOINT \
  --bootstrap-region-id $KEYSTONE_REGION

  
  # Copy keystone's public endpoint wsgi conf
  ln -s /usr/share/keystone/wsgi-keystone.conf /etc/httpd/conf.d/
  
  # Ryan the fire starter

  }


function keystone_pipeline(){
  if [ ! -f /tmp/keystone_done ] ; then 
    package_installing
    sql
    keystone_setup
  fi

  end=$(date +%s)
  echo "EoF for $OS_VERSION BOOTSTRAPING (started: $start, ended: $end, took $(expr $end - $start) secs   )"
  httpd -DFOREGROUND

  ryans_token=$(openstack token issue -f value  --os-auth-url $KEYSTONE_INTERNAL_ENDPOINT --os-identity-api-version 3 --os-project-domain-name Default --os-user-domain-name Default --os-project-name admin --os-password $ADMIN_PASS --os-username admin|grep '^gAAA')
  alias openstack="--os-token $ryans_token --os-url $KEYSTONE_PUBLIC_ENDPOINT"

  openstack domain create --description "An Example Domain" example
  openstack project create --domain default --description "Service Project" service 
  openstack project create --domain default --description "Demo Project" myproject
  openstack user create --domain default --password myuserpass myuser
  openstack role create myrole
  openstack role add --project myproject --user myuser myrole


  }


keystone_pipeline
