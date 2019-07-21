start=$(date +%s)
#!/bin/bash

function package_installing(){
  apt-get update 
  apt-get install -y netcat mariadb-client gcc libssl-dev
  cd /tmp
  git clone -b stable/rocky https://github.com/openstack/keystone.git
  cd keystone
  pip install -r requirements.txt
  python setup.py install
  echo "###########################"
  echo "# PACKAGE INSTALL IS DONE #"
  echo "###########################"
}


function keystone_create_db(){
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e" GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
  unset -v MYSQL_ROOT_PASSWORD MYSQL_ALLOW_EMPTY_PASSWORD KEYSTONE_DB_NAME KEYSTONE_DB_USER KEYSTONE_USER_DB_PASS
  }


function sql_connection_test(){ 
	nc -z $MYSQL_HOST $MYSQL_PORT 
	}

function bootstrap_pipeline(){ 
	keystone_create_db
	echo "EoF bootstrap pipeline"
	}


package_installing


end=$(date +%s)
echo "EoF BOOTSTRAPING(started: $start, ended: $end, took $(expr $end - $start) secs   )"
