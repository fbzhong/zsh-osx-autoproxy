#!/bin/bash

export PATH=$PATH:/opt/homebrew/bin:/opt/local/bin

SOCAT_ARGS="-T180"

if [[ $1 == 10.* ]] || [[ $1 == 192.168.* ]] || [[ $1 =~ ^172\.(1[6-9]|2[0-9]|3[01])\..* ]] || [ "${SOCAT_PROXY:-$socat_proxy}" == "" ] || [ "${SOCAT_PROXY:-$socat_proxy}" == "PROXY:" ]; then
    socat $SOCAT_ARGS - TCP-CONNECT:$1:$2
else
    socat $SOCAT_ARGS - ${SOCAT_PROXY:-$socat_proxy}:$1:$2,${SOCAT_PROXY_PORT:-$socat_proxy_port},retry=3
fi
