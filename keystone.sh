#!/bin/bash
start=$(date +%s)
echo "#########################################"
echo "#######    INSTALLING STARTED $start"
echo "#########################################"

start=$(date +%s)
DOCKER_HOST_ADDR=$(echo "$DOCKER_HOST" |awk -F'//' {'print $2'}|awk -F':' {'print $1'})

    yum install -y centos-release-openstack-$OS_VERSION  python-openstackclient httpd mod_wsgi mariadb
    yum install -y openstack-keystone mod_ssl
    echo "# INFO: Package installing is done. #"

function create_keystone_db(){
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $KEYSTONE_DB_NAME;"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'%' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    mysql -u root -h $MYSQL_HOST -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $KEYSTONE_DB_NAME.* TO '$KEYSTONE_DB_USER'@'localhost' IDENTIFIED BY '$KEYSTONE_USER_DB_PASS';"
    echo "# INFO: DB creating is done. #"
    }

function check_permissions(){
# https://docs.openstack.org/security-guide/identity/checklist.html

    chown -R keystone:keystone /etc/keystone

    echo "INFO: All directories to be set 750"
    for directory in $(find /etc/keystone/ -type d) ; do
      chmod 0750 $directory
      echo $directory permission: $(stat -L -c "%a" $directory), Ownership: $(stat -L -c "%U %G" $directory | egrep "keystone keystone")
      done

    echo "INFO: All files to be set 640"
    for file in $(find /etc/keystone/ -type f) ;
      do
        chmod 0640 $file
        echo $file permission: $(stat -L -c "%a" $file), Ownership: $(stat -L -c "%U %G" $file | egrep "keystone keystone")
      done

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

            # PoW CaCert and Key
cat <<EoF > $tls_dir/server.key
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDF5vLSSvAZY/OD
bUsCCaSGqGm94eQWWYFUVqrzOBXKvS+QOBiZELqURG2kwjDpO1ZR+WvQkgiKSyLu
AtFTwPr8nkFUKT+9aU6M/LS6vRmkZoNEAJE+E6nrOCI7SOUweczwZiuCdRnDfah+
qObQ5FLlTdp99IsX+j1WfNErZ+GcMqQQojhGbPJqdA7KYHL6dS6jtQeDf0/O9nR4
G4WNhzU+efFxW2duAtkFT2Ur8fcGrPqjaU6QxAkCHxRrhLwxEBm9eMRE84pHDrZc
gEvPTKKcODD3o3hnJ9nSNoPxnwJisNJSv9dtLlpqXuICCmUXGoaz2kcoy3NbgBEk
D/wFpVIvAgMBAAECggEAXrHemM9wycVw3P9r98KjbiehyVEQcb1MTA3YaN76VnNm
Ee01n/BIRu/jQwYEn2VcLYdalod5/KptQVQp05iwwDX9bob6T+jWxFGbLQuU/Hxs
7RoUZY7FLJ9EifecazCs5o8M3LSpqkgzWr/5ChVmsQAqv0BHWibMONkqwUlIxBMC
EQZB2guDQ5x9CHx0SwKp52B2e5V0ezM1kuR8a9PBfy8YdxCPR+I/BCnkDvDY+VrS
NjKbUIvaFPypkr9ds4XpQLO041inSpczxm4PW83tuCoaHarhlVtJsoIsvXmQkedH
cKaZWefJe3G/KBk9nmRp7XYjZUq59+NUtnzBa8kQ0QKBgQD/yQUyjH3iNjlaTLLF
BI3ROk+PNtqK9E3iEFhmtmFhHgX7UGnn23Bv1lbeGJe8j+hBauXO2VzCS8O8Cbn+
IqEnb/Io6+//w+dzxOa6UbXFb5HCtW5/L2Wt4dgiAnmJcncBrx1/6gbI1bNiZNK/
n3C8q9BmQhgBmsJJ375UWZCMtwKBgQDGEXyOmgceYg+17YwjLUTnPHYZpJb9B7lC
jpqPv2HeY4k2xjrkzgfeVbtjoYVhp8aYtI1ACBDcNEG9ZvwFnmZ7lXaPiN9GAptA
r1c7tZjPjpCdj1ouSXVDOywPgHJMipMpd5NFnzYjLOKY7jRXqfNGTkbrGiFSwlbE
IBoLuE5eSQKBgDk+eM5OSOH2drFx1tRm54I6xZFsmk5czI1aUR5zlKmSeY47+ees
4aX11y0PXe4SWs1BKjs3xB2rrRuJJbntcBmOYSitXOHlqwfquiRaow6ToJBt4FPQ
fLYEhEVgPmj3WBDlavm0m14ZDXNo0w2VljpzTUmFYzAAvZig3UytWr9TAoGBALiS
LP75265ddQR0c4WINtBAkFE/BhCOdP3nw3I2xq2lFYV8Xf8/Wye9vlyOdKvW24ML
pSDJI2UAMU6dPDbEL/3z/sKsqlskLKavflu+0sJ/uJWKs1+0xlg7OMjNSjW3YIFg
01UqkxleR155gz85uOCIKyAEfo8PWCl1PLA1NJo5AoGAY3jq/SB/UFWIFaWoFuKc
LzQC6CkKEj7ptNVh2FR5ouuPDoqG2yq+97lyGYasfJE5I7aCYmrlhKx+c5CX+6ci
7/bXlqMu+dd/RrsBp+ivgSykXiHv3KQ9DAvDbnLCjcMog/KgkwZjNMS4zG0Xph6W
29kSzf64WlETjUvTeggwhvQ=
-----END PRIVATE KEY-----
EoF

 cat <<EoF > $tls_dir/server.crt
-----BEGIN CERTIFICATE-----
MIIEATCCAumgAwIBAgIJANs2BMoeFmegMA0GCSqGSIb3DQEBCwUAMIGWMQswCQYD
VQQGEwJVUzELMAkGA1UECAwCTlkxDDAKBgNVBAcMA05ZQzEWMBQGA1UECgwNU25h
a2UgT2lsIENvLjEeMBwGA1UECwwVU25ha2UgT2lsIENsb3VkIERlcHQuMRIwEAYD
VQQDDAlsb2NhbGhvc3QxIDAeBgkqhkiG9w0BCQEWEXJvb3RAc25ha2VvaWwuY29t
MB4XDTE5MDgxMzIxNTM0NFoXDTIwMDgxMjIxNTM0NFowgZYxCzAJBgNVBAYTAlVT
MQswCQYDVQQIDAJOWTEMMAoGA1UEBwwDTllDMRYwFAYDVQQKDA1TbmFrZSBPaWwg
Q28uMR4wHAYDVQQLDBVTbmFrZSBPaWwgQ2xvdWQgRGVwdC4xEjAQBgNVBAMMCWxv
Y2FsaG9zdDEgMB4GCSqGSIb3DQEJARYRcm9vdEBzbmFrZW9pbC5jb20wggEiMA0G
CSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDF5vLSSvAZY/ODbUsCCaSGqGm94eQW
WYFUVqrzOBXKvS+QOBiZELqURG2kwjDpO1ZR+WvQkgiKSyLuAtFTwPr8nkFUKT+9
aU6M/LS6vRmkZoNEAJE+E6nrOCI7SOUweczwZiuCdRnDfah+qObQ5FLlTdp99IsX
+j1WfNErZ+GcMqQQojhGbPJqdA7KYHL6dS6jtQeDf0/O9nR4G4WNhzU+efFxW2du
AtkFT2Ur8fcGrPqjaU6QxAkCHxRrhLwxEBm9eMRE84pHDrZcgEvPTKKcODD3o3hn
J9nSNoPxnwJisNJSv9dtLlpqXuICCmUXGoaz2kcoy3NbgBEkD/wFpVIvAgMBAAGj
UDBOMB0GA1UdDgQWBBQ61yc0sehWXLBrC2pjNsncultQSzAfBgNVHSMEGDAWgBQ6
1yc0sehWXLBrC2pjNsncultQSzAMBgNVHRMEBTADAQH/MA0GCSqGSIb3DQEBCwUA
A4IBAQA1cCpCbRguYmyz5lRlGefRp0ymUvU9ne+84Ezuv7MiuT16W7jmHktJykQR
sLrvkxGWVv+tvIhCZdJvWmTc/BWHNEWMfCmTY8azHBjx+pGawSg6xr3zLAd3ioDY
NUHjg4k8M2LfcmZdAL0QpALe29yFfj9C3fBIf6ONGBJWfWjL7s/Rs3wHyffOr7Iq
Jlb69csSZHyiecz4Hvk7Nh3GhOaNNAgzpnZzx2IOHSZlqjvYx98b5Q30bQp14Nzm
Y8G+falGftFT4dUavRvvXvbTJQ9/3cl4B8jEw418mSSW/J8Za5xD/I7srIKc+m1k
eVofIIhh2eqUZ2MaUdVn2LCiYjEq
-----END CERTIFICATE-----
EoF



#            echo "
#            [req]
#            distinguished_name = req_distinguished_name
#            x509_extensions = v3_req
#            prompt = no
#            [req_distinguished_name]
#            C = US
#            ST = NY
#            L = New Dork City
#            O = Snake Oil Inc.
#            OU = Kelly's nook
#            CN = localhost
#            [v3_req]
#            keyUsage = keyEncipherment, dataEncipherment
#            extendedKeyUsage = serverAuth
#            subjectAltName = @alt_names
#
#            [alt_names]
#            IP.1 = 10.0.0.71
#            IP.2 = 10.0.0.72
#            IP.3 = 10.0.0.73
#            " > $tls_dir/os.cnf
#            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -config $tls_dir/os.cnf -keyout $tls_dir/server.key -out $tls_dir/server.crt

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


    }

main






