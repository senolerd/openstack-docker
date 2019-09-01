#!/usr/bin/env bash
cur_dir=$base/branches/$OS_VERSION/etc

banner(){
  theme="@"
  lrPadding=2
  sentenceLen=$(expr $(echo $title | wc -m ) - 1  )
  bannerLen=$(expr $lrPadding + $sentenceLen +  $lrPadding + 2 )
  for i in $(seq 1 $bannerLen);do printf "$theme";done;printf "\n$theme";
  for i in $(seq 1 $lrPadding);do printf " ";done;printf "$title"
  for i in $(seq 1 $lrPadding);do printf " ";done;echo "$theme";
  for i in $(seq 1 $bannerLen);do printf "$theme";done;echo
}

create_root_ca(){ 

    title="Root CA: Prepare the directory.";banner
    rm -rf $cur_dir/ca
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
    echo "OK"

    title="Root CA: Create private key.";banner
    openssl genrsa -out $cur_dir/ca/private/ca.key.pem 4096 -nodes
    chmod 400 $cur_dir/ca/private/ca.key.pem
    echo "OK"

    title="Root CA: Create self-signed certificate.";banner
    SUBJ="/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/L=$LOCAL_NAME/O=$COMPANY_NAME/OU=$COMPANY_NAME Root Certificate Authority/CN=$COMPANY_NAME Root CA"
    openssl req  -config $cur_dir/ca/openssl.cnf \
             -key $cur_dir/ca/private/ca.key.pem \
             -new -x509 -days 7300 -sha256 -extensions v3_ca \
             -out $cur_dir/ca/certs/ca.cert.pem -nodes -subj "$SUBJ"
    chmod 444 $cur_dir/ca/certs/ca.cert.pem
    echo "OK"

    title="Root CA: Verify the certificate.";banner
    openssl x509 -noout -text -in $cur_dir/ca/certs/ca.cert.pem
    }
    
create_intermediate_ca(){
    title="Intermediate CA: Prepare the directory.";banner
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
    echo "OK"

    title="Intermediate CA: Create private key.";banner
    openssl genrsa -out $cur_dir/ca/intermediate/private/intermediate.key.pem 4096 -nodes
    chmod 400 $cur_dir/ca/intermediate/private/intermediate.key.pem
     

    title="Intermediate CA: Create CSR.";banner
    SUBJ="/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/L=$LOCAL_NAME/O=$COMPANY_NAME/OU=$COMPANY_NAME Intermediate Certificate Authority/CN=$COMPANY_NAME Intermediate CA"
    openssl req -config $cur_dir/ca/intermediate/openssl.cnf -new -sha256 \
          -key $cur_dir/ca/intermediate/private/intermediate.key.pem \
          -out $cur_dir/ca/intermediate/csr/intermediate.csr.pem -nodes -subj "$SUBJ"
    echo "OK"    

    title="Intermediate CA: Create certificate signed Root CA.";banner
    openssl ca  -config $cur_dir/ca/openssl.cnf -extensions v3_intermediate_ca \
          -days 3650 -notext -md sha256 \
          -in $cur_dir/ca/intermediate/csr/intermediate.csr.pem \
          -out $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    chmod 444  $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    echo "OK"    
    


    title="Intermediate CA: Verify the certificate.";banner
    openssl x509 -noout -text -in $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    
    title="Intermediate CA: Verify the certificate against Root certificate.";banner
    openssl verify -CAfile $cur_dir/ca/certs/ca.cert.pem $cur_dir/ca/intermediate/certs/intermediate.cert.pem
    
    title="Intermediate CA: Create CA chain certificate.";banner
    cat $cur_dir/ca/intermediate/certs/intermediate.cert.pem \
             $cur_dir/ca/certs/ca.cert.pem > $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    chmod 444 $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    echo "OK"    

    title="Intermediate CA: CA chain certificate.";banner
    cat $cur_dir/ca/intermediate/certs/ca-chain.cert.pem
    }


create_server_cert(){
    title="$target_host: Create private key.";banner
    openssl genrsa -out $cur_dir/ca/intermediate/private/$target_host.key.pem 2048 -nodes
    chmod 400 $cur_dir/ca/intermediate/private/$target_host.key.pem
    echo "OK"    

    title="$target_host: Create the CSR.";banner
    SUBJ="/CN=$target_host/OU=$COMPANY_NAME Openstack Cloud/C=$COUNTRY_NAME/ST=$STATE_OR_PROVINCE/O=$COMPANY_NAME/L=$LOCAL_NAME"
    openssl req -config $cur_dir/ca/intermediate/openssl.cnf -nodes \
          -key $cur_dir/ca/intermediate/private/$target_host.key.pem \
          -new -sha256 -out  $cur_dir/ca/intermediate/csr/$target_host.csr.pem -subj "$SUBJ"
    echo "OK"    
    
    title="$target_host: Create certificate signed Intermediate CA.";banner
    sed -i "s/cert ]/cert ]\nsubjectAltName=DNS:$target_host,IP:$DOCKER_HOST_ADDR/" $cur_dir/ca/intermediate/openssl.cnf
    openssl ca -config $cur_dir/ca/intermediate/openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in $cur_dir/ca/intermediate/csr/$target_host.csr.pem \
      -out $cur_dir/ca/intermediate/certs/$target_host.cert.pem 
    chmod 444 $cur_dir/ca/intermediate/certs/$target_host.cert.pem
    echo "OK"    

    title="$target_host: Verifying the certificate.";banner
    openssl x509 -noout -text -in $cur_dir/ca/intermediate/certs/$target_host.cert.pem
   }

create_root_ca
create_intermediate_ca
create_server_cert
find $cur_dir/ca 

echo "TLS is done"

