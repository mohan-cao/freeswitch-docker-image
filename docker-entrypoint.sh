#!/bin/bash

set -e

# Source docker-entrypoint.sh:
# https://github.com/docker-library/postgres/blob/master/9.4/docker-entrypoint.sh
# https://github.com/kovalyshyn/docker-freeswitch/blob/vanilla/docker-entrypoint.sh

if [ "$1" = 'freeswitch' ]; then
    if [ ! -f "/etc/freeswitch/freeswitch.xml" ]; then
        mkdir -p /etc/freeswitch
        cp -varf /usr/share/freeswitch/conf/vanilla/* /etc/freeswitch/
	rm -rf /usr/share/freeswitch/conf
	echo "Copying vanilla config for freeswitch xml"
    fi
    
    chown -R freeswitch:freeswitch /usr/local/freeswitch

    if [ -d /docker-entrypoint.d ]; then
        for f in /docker-entrypoint.d/*.sh; do
            [ -f "$f" ] && . "$f"
        done
    fi

    exec gosu freeswitch /usr/bin/freeswitch -u freeswitch -g freeswitch \
        -conf /etc/freeswitch \
	-db /usr/local/freeswitch/db \
        -log /usr/local/freeswitch/log \
	-nonat -c -nf
fi

exec "$@"
