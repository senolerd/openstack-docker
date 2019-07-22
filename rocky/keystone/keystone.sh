start=$(date +%s)
#!/bin/bash

function package_installing(){
  apt-get update 
  # apt-get install -y netcat mariadb-client gcc libssl-dev libldap2-dev libsasl2-dev tox
  cd /tmp
  git clone -b stable/rocky https://github.com/openstack/keystone.git
  cd keystone
  pip install -r requirements.txt
  python setup.py install
  echo "###########################"
  echo "# PACKAGE INSTALL IS DONE #"
  echo "###########################"
}


function create_keystone_db(){
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  echo "###########################"
  echo "# DB CREATING IS DONE     #"
  echo "###########################"
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
# chown -R keystone:keystone /var/lib/keystone
  chown -R keystone:keystone /etc/keystone
}


function keystone_setup(){
  useradd --home-dir "/var/lib/keystone" --create-home --system --shell /bin/false keystone
  mkdir -p /var/log/keystone
  mkdir -p /etc/keystone
  cd /tmp/keystone
  tox -egenconfig
  cp etc/* /etc/keystone/
  cp /etc/keystone/keystone.conf.sample /etc/keystone/keystone.conf
  sed -i "s|database]|database]\nconnection = mysql+pymysql://$KEYSTONE_DB_USER:$KEYSTONE_USER_DB_PASS@$MYSQL_HOST/$KEYSTONE_DB_NAME|g" /etc/keystone/keystone.conf
  sed -i "s|token]|token]\nprovider = fernet|g" /etc/keystone/keystone.conf
  check_permissions

  su -s /bin/sh -c "keystone-manage db_sync" keystone
  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

  }

package_installing
sql
keystone_setup


end=$(date +%s)
echo "EoF BOOTSTRAPING(started: $start, ended: $end, took $(expr $end - $start) secs   )"
