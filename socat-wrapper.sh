#!/bin/bash

if [ "${socat_proxy}" == "" ]; then
    socat - tcp-connect:$1:$2
else
    socat - ${socat_proxy}:$1:$2,${socat_proxy_port}
fi
