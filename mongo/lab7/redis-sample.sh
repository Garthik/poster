#!/bin/sh
set -eu
# A private disposable Redis instance uses a Unix socket and publishes no ports.
redis-server --port 0 --unixsocket /tmp/lab7.sock --save '' --appendonly no --daemonize yes --logfile /tmp/redis.log
redis-cli -s /tmp/lab7.sock --raw --eval /work/redis-sample.lua , "$(cat /evidence/redis-source.json)" "$(date -u +%F)"
