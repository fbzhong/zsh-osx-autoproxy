#!/bin/bash

export PATH=$PATH:/opt/homebrew/bin:/opt/local/bin

if [[ $1 == 10.* ]] || [[ $1 == 192.168.* ]] || [ "${SOCAT_PROXY:-$socat_proxy}" == "" ] || [ "${SOCAT_PROXY:-$socat_proxy}" == "PROXY:" ]; then
    socat - TCP-CONNECT:$1:$2
else
    socat - ${SOCAT_PROXY:-$socat_proxy}:$1:$2,${SOCAT_PROXY_PORT:-$socat_proxy_port},retry=3
fi
