#!/usr/bin/env bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -config $base/etc/os_opnssl.cnf -keyout $base/etc/server.key -out $base/etc/server.crt
