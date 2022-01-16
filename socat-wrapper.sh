#!/bin/bash

export PATH=$PATH:/usr/local/bin:/opt/local/bin:/opt/homebrew/bin

if [[ $1 == 10.* ]] || [[ $1 == 192.168.* ]] || [ "${SOCAT_PROXY:-$socat_proxy}" == "" ] || [ "${SOCAT_PROXY:-$socat_proxy}" == "proxy:" ]; then
    socat - tcp-connect:$1:$2
else
    socat - ${SOCAT_PROXY:-$socat_proxy}:$1:$2,${SOCAT_PROXY_PORT:-$socat_proxy_port}
fi
