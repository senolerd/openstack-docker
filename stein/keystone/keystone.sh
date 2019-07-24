#!/bin/bash
start=$(date +%s)

function package_installing(){
  apt-get update 
  cd /tmp
  git clone -b stable/$OS_VERSION https://github.com/openstack/keystone.git
  cd keystone
  pip install -r requirements.txt
  python setup.py install
  echo "# PACKAGE INSTALL IS DONE #"
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
        echo "Waiting for SQL server up.. Last try: $(date)"
        sleep 1
      fi
    done
  }


function check_permissions(){
  chown -R keystone:keystone /var/log/keystone
  chown -R keystone:keystone /etc/keystone
}


function keystone_setup(){
  useradd --home-dir "/var/lib/keystone" --create-home --system --shell /bin/false keystone
  mkdir -p /var/log/keystone
  mkdir -p /etc/keystone
  cd /tmp/keystone
  tox -egenconfig
  cp etc/* /etc/keystone/
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

  cp httpd/wsgi-keystone.conf /etc/apache2/sites-enabled/
  touch /tmp/keystone_done
  }


function keystone_pipeline(){
  if [ ! -f /tmp/keystone_done ] ; then 
    package_installing
    sql
    keystone_setup
  fi

  end=$(date +%s)
  echo "EoF for $OS_VERSION BOOTSTRAPING (started: $start, ended: $end, took $(expr $end - $start) secs   )"
  /etc/init.d/apache2 start
  }


keystone_pipeline
