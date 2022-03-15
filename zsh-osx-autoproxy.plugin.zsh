#!/bin/zsh
# Auto configure zsh proxy env based on system preferences
# Sukka (https://skk.moe)

proxy () {
    # Cache the output of scutil --proxy
    __ZSH_OSX_AUTOPROXY_SCUTIL_PROXY=$(scutil --proxy)

    # Pattern used to match the status
    __ZSH_OSX_AUTOPROXY_HTTP_PROXY_ENABLED_PATTERN="HTTPEnable : 1"
    __ZSH_OSX_AUTOPROXY_HTTPS_PROXY_ENABLED_PATTERN="HTTPSEnable : 1"
    __ZSH_OSX_AUTOPROXY_FTP_PROXY_ENABLED_PATTERN="FTPSEnable : 1"
    __ZSH_OSX_AUTOPROXY_SOCKS_PROXY_ENABLED_PATTERN="SOCKSEnable : 1"

    __ZSH_OSX_AUTOPROXY_HTTP_PROXY_ENABLED=$__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY[(I)$__ZSH_OSX_AUTOPROXY_HTTP_PROXY_ENABLED_PATTERN]
    __ZSH_OSX_AUTOPROXY_HTTPS_PROXY_ENABLED=$__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY[(I)$__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_ENABLED_PATTERN]
    __ZSH_OSX_AUTOPROXY_FTP_PROXY_ENABLED=$__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY[(I)$__ZSH_OSX_AUTOPROXY_FTP_PROXY_ENABLED_PATTERN]
    __ZSH_OSX_AUTOPROXY_SOCKS_PROXY_ENABLED=$__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY[(I)$__ZSH_OSX_AUTOPROXY_SOCKS_PROXY_ENABLED_PATTERN]

    # http proxy
    if (( $__ZSH_OSX_AUTOPROXY_HTTP_PROXY_ENABLED )); then
        __ZSH_OSX_AUTOPROXY_HTTP_PROXY_SERVER=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*HTTPProxy : }[(f)1]}
        __ZSH_OSX_AUTOPROXY_HTTP_PROXY_PORT=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*HTTPPort : }[(f)1]}
        export http_proxy="http://${__ZSH_OSX_AUTOPROXY_HTTP_PROXY_SERVER}:${__ZSH_OSX_AUTOPROXY_HTTP_PROXY_PORT}"
        export HTTP_PROXY="${http_proxy}"
    fi
    # https_proxy
    if (( $__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_ENABLED )); then
        __ZSH_OSX_AUTOPROXY_HTTPS_PROXY_SERVER=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*HTTPSProxy : }[(f)1]}
        __ZSH_OSX_AUTOPROXY_HTTPS_PROXY_PORT=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*HTTPSPort : }[(f)1]}
        export https_proxy="http://${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_SERVER}:${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_PORT}"
        export HTTPS_PROXY="${https_proxy}"
    fi
    # ftp_proxy
    if (( $__ZSH_OSX_AUTOPROXY_FTP_PROXY_ENABLED )); then
        __ZSH_OSX_AUTOPROXY_FTP_PROXY_SERVER=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*FTPProxy : }[(f)1]}
        __ZSH_OSX_AUTOPROXY_FTP_PROXY_PORT=${${__ZSH_OSX_AUTOPROXY_SCUTIL_PROXY#*FTPPort : }[(f)1]}
        export ftp_proxy="http://${__ZSH_OSX_AUTOPROXY_FTP_PROXY_SERVER}:${__ZSH_OSX_AUTOPROXY_FTP_PROXY_PORT}"
        export FTP_PROXY="${ftp_proxy}"
    fi

    if (( $__ZSH_OSX_AUTOPROXY_HTTP_PROXY_ENABLED )); then
        http_proxy_address="${__ZSH_OSX_AUTOPROXY_HTTP_PROXY_SERVER}:${__ZSH_OSX_AUTOPROXY_HTTP_PROXY_PORT}"

        export all_proxy="${http_proxy}"
        export ALL_PROXY="${all_proxy}"

        export rsync_proxy="${http_proxy_address}"
        export RSYNC_PROXY="${http_proxy_address}"
    fi

    if (( $__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_ENABLED )); then
        http_proxy_address="${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_SERVER}:${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_PORT}"

        export all_proxy="${http_proxy}"
        export ALL_PROXY="${all_proxy}"

        export rsync_proxy="${http_proxy_address}"
        export RSYNC_PROXY="${http_proxy_address}"

        export socat_proxy="proxy:${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_SERVER}"
        export socat_proxy_port="proxyport=${__ZSH_OSX_AUTOPROXY_HTTPS_PROXY_PORT}"

        export SOCAT_PROXY="${socat_proxy}"
        export SOCAT_PROXY_PORT="${socat_proxy_port}"

        export GIT_PROXY_COMMAND="${0:a:h}/socat-wrapper.sh"
    fi
}

noproxy () {
    unset {http,https,ftp,rsync,all,}_proxy {HTTP,HTTPS,FTP,RSYNC,ALL}_PROXY socat_proxy{,_port} SOCAT_PROXY{,_PORT} GIT_PROXY_COMMAND
}

# enable proxy env by default.
proxy
