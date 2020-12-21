#!/bin/bash

if [ "${SOCAT_PROXY:-$socat_proxy}" == "" ]; then
    socat - tcp-connect:$1:$2
else
    socat - ${SOCAT_PROXY:-$socat_proxy}:$1:$2,${SOCAT_PROXY_PORT:-$socat_proxy_port}
fi
