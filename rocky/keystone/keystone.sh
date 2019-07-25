#!/bin/bash
# this line will be removed
start=$(date +%s)

function package_installing(){
  yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient openstack-keystone httpd mod_wsgi mariadb
  echo "# DB CREATING IS DONE     #"
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
      if nc -z $MYSQL_HOST $MYSQL_PORT; then
        create_keystone_db 
        break
      else
        echo "Waiting for SQL server up.. Last trying time: $(date)"
        sleep 1
      fi
    done
  }


function check_permissions(){
  chown -R keystone:keystone /etc/keystone
}


function keystone_setup(){
  cp /etc/keystone/logging.conf.sample /etc/keystone/logging.conf
  cp /etc/keystone/keystone.conf.sample /etc/keystone/keystone.conf
  sed -i "s|^\[database]|[database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
  sed -i "s|^\[token]|[token]\nprovider = fernet|g" /etc/keystone/keystone.conf

  check_permissions

  su -s /bin/sh -c "keystone-manage db_sync" keystone
  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

  keystone-manage bootstrap --bootstrap-password adminpass \
  --bootstrap-public-url $KEYSTONE_PUBLIC_ENDPOINT \
  --bootstrap-region-id $KEYSTONE_REGION

  }


function keystone_pipeline(){
  if [ ! -f /tmp/keystone_done ] ; then 
    package_installing
#    sql
#    keystone_setup
  fi

  end=$(date +%s)
  echo "EoF for $OS_VERSION BOOTSTRAPING (started: $start, ended: $end, took $(expr $end - $start) secs   )"
#  /etc/init.d/apache2 start
   sleep 666d
  }


keystone_pipeline
