start=$(date +%s)
#!/bin/bash
function installing(){
  apt-get update 
  apt-get install netcat mariadb-client gcc libssl-dev
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

function bootstrap_pipeline(){ 
	installing
	keystone_create_db
	echo "EoF bootstrap pipeline"
	}

function sql_connection_test(){ 
	nc -z $MYSQL_HOST $MYSQL_PORT 
	}

function prepre_to_bootstrap(){
  while true
    do
      if sql_connection_test
        then
          bootstrap_pipeline        
          break
      fi

      echo "Connection test to sql server.. [ Last attempt: `date +%H:%M:%S` ]"
      sql_connection_test
      sleep 3
    done
}


end=$(date +%s)
prepre_to_bootstrap
echo "EoF BOOTSTRAPING(started: $start, ended: $end, took $(expr $end - $start) secs   )"
