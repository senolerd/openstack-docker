#!/usr/bin/env bash
cur_dir=$base/branches/$OS_VERSION/etc
create_root_ca(){ 
    echo -e "\n### Root CA cert begin ###"
    rm -rf $cur_dir/ca
    # Prepare the directory
    mkdir -p $cur_dir/ca/{certs,crl,newcerts,private}
    
    cd $cur_dir/ca
    chmod 700 private
    touch index.txt
    echo 1000 > serial
    
    sed    -e "s,/root/ca,$cur_dir/ca," \
           -e "s,COMPANY_NAME,$COMPANY_NAME," \
           -e "s,COUNTRY_NAME,$COUNTRY_NAME," \
           -e "s,STATE_OR_PROVINCE,$STATE_OR_PROVINCE," \
           -e "s,LOCAL_NAME,$LOCAL_NAME," $cur_dir/openssl_root_ca_template.cnf > $cur_dir/ca/openssl.cnf 

    openssl genrsa -out $cur_dir/ca/private/ca.key.pem 4096 -nodes
    chmod 400 $cur_dir/ca/private/ca.key.pem
    echo "root CA key OK"
    
   SUBJ="/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/L=$LOCAL_NAME/O=$COMPANY_NAME/OU=$COMPANY_NAME Root Certificate Authority/CN=$COMPANY_NAME Root CA"
   openssl req  -config $cur_dir/ca/openssl.cnf \
             -key $cur_dir/ca/private/ca.key.pem \
             -new -x509 -days 7300 -sha256 -extensions v3_ca \
             -out $cur_dir/ca/certs/ca.cert.pem -nodes -subj "$SUBJ"

    chmod 444 $cur_dir/ca/certs/ca.cert.pem
    openssl x509 -noout -text -in $cur_dir/ca/certs/ca.cert.pem
    echo "\n### Root CA cert OK ###\n"
    }
    
create_intermediate_ca(){
    echo -e "\n### Intermediate CA starts ###"
    # Create the intermediate directoryies
    mkdir -p $cur_dir/ca/intermediate/{certs,crl,csr,newcerts,private}
    cd $cur_dir/ca/intermediate
    chmod 700 private
    touch index.txt
    echo 1000 > serial
    echo 1000 > $cur_dir/ca/intermediate/crlnumber
    
    sed -e "s,INTERMEDIATE_CA_DIR,$cur_dir/ca/intermediate," \
        -e "s,COMPANY_NAME,$COMPANY_NAME," \
        -e "s,COUNTRY_NAME,$COUNTRY_NAME," \
        -e "s,STATE_OR_PROVINCE,$STATE_OR_PROVINCE," \
        -e "s,LOCAL_NAME,$LOCAL_NAME," $cur_dir/openssl_intermediate_ca_template.cnf > $cur_dir/ca/intermediate/openssl.cnf 

    echo "Intermediate CA conf OK"
    
    openssl genrsa -out $cur_dir/ca/intermediate/private/intermediate.key.pem 4096 -nodes
    chmod 400 $cur_dir/ca/intermediate/private/intermediate.key.pem
    echo "Intermediate CA key OK"
     
    echo -e "\n### Create the intermediate CA CSR ###"

    SUBJ="/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/L=$LOCAL_NAME/O=$COMPANY_NAME/OU=$COMPANY_NAME Intermediate Certificate Authority/CN=$COMPANY_NAME Intermediate CA"

    openssl req -config $cur_dir/ca/intermediate/openssl.cnf -new -sha256 \
          -key $cur_dir/ca/intermediate/private/intermediate.key.pem \
          -out $cur_dir/ca/intermediate/csr/intermediate.csr.pem -nodes -subj "$SUBJ"
    echo "Intermediate CSR OK"
    
    echo "\n### Intermediate CERT sign start ###"
    openssl ca  -config $cur_dir/ca/openssl.cnf -extensions v3_intermediate_ca \
          -days 3650 -notext -md sha256 \
          -in $cur_dir/ca/intermediate/csr/intermediate.csr.pem \
          -out $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    chmod 444  $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    echo "### Intermediate CERT sign OK ###"
    
    openssl x509 -noout -text -in $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    
    printf "Intermediate CERT verifing against root certificate: "
    openssl verify -CAfile $cur_dir/ca/certs/ca.cert.pem $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    
    cat $cur_dir/ca/intermediate/certs/intermediate.cert.pem \
             $cur_dir/ca/certs/ca.cert.pem > $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    chmod 444 $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    echo "CERT CHAIN"
    echo -e "\n"
    cat $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    echo -e "\n#### Intermediate CA done #####"
    }

create_server_cert(){
    echo -e "\n### Server certificate started for $server ###"
    # Create a key
    openssl genrsa -out $cur_dir/ca/intermediate/private/$server.key.pem 2048 -nodes
    chmod 400 $cur_dir/ca/intermediate/private/$server.key.pem
    echo "Server key created for $server"

   SUBJ="/CN=$target_host/OU=$COMPANY_NAME Openstack Cloud/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/O=$COMPANY_NAME/L=$LOCAL_NAME"
    
    # Create a CSR for signed by intermediate CA
    openssl req -config $cur_dir/ca/intermediate/openssl.cnf -nodes \
          -key $cur_dir/ca/intermediate/private/$server.key.pem \
          -new -sha256 -out  $cur_dir/ca/intermediate/csr/$server.csr.pem -subj "$SUBJ"
    
    echo "CSR created for $server"

    sed -i "s/cert ]/cert ]\nsubjectAltName=DNS:$target_host,IP:$DOCKER_HOST_ADDR/" $cur_dir/ca/intermediate/openssl.cnf

    echo "Certificate  creating for $server"

    openssl ca -config $cur_dir/ca/intermediate/openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in $cur_dir/ca/intermediate/csr/$server.csr.pem \
      -out $cur_dir/ca/intermediate/certs/$server.cert.pem 

    echo "Certificate creating done for  $server"
    chmod 444 $cur_dir/ca/intermediate/certs/$server.cert.pem
    openssl x509 -noout -text -in $cur_dir/ca/intermediate/certs/$server.cert.pem
    echo -e "\nServer certificate is done for $server"
   }

if [ -z $server ];then
  create_root_ca
  create_intermediate_ca
else
  create_server_cert
fi

find $cur_dir/ca
echo "TLS is done"

