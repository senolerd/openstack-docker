#!/usr/bin/env bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -config $base/branches/$OS_VERSION//etc/os_opnssl.cnf -keyout $base/branches/$OS_VERSION//etc/server.key -out $base/branches/$OS_VERSION//etc/server.crt
