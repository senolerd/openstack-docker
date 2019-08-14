#!/usr/bin/env bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -config tls/os_opnssl.cnf -keyout tls/server.key -out tls/server.crt