#!/bin/bash
set -e

# Source docker-entrypoint.sh:
# https://github.com/docker-library/postgres/blob/master/9.4/docker-entrypoint.sh
# https://github.com/kovalyshyn/docker-freeswitch/blob/vanilla/docker-entrypoint.sh

if [ "$1" = 'freeswitch' ]; then
    if [ ! -f "/etc/freeswitch/freeswitch.xml" ]; then
        mkdir -p /etc/freeswitch
        cp -varf /usr/share/freeswitch/conf/vanilla/* /etc/freeswitch/
    fi
    if [ -d /docker-entrypoint.d ]; then
        for f in /docker-entrypoint.d/*.sh; do
            [ -f "$f" ] && . "$f"
        done
    fi

    /usr/bin/freeswitch -nonat -c -nf
fi

exec "$@"
