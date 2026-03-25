#!/usr/bin/env zsh
# Auto configure zsh proxy env based on system preferences
# Sukka (https://skk.moe)

# Optimized noproxy function: Uses zsh-specific parameter expansion for case handling.
noproxy () {
    local quiet_mode=${1:-0} # 0 = verbose (default), 1 = quiet
    local -a lower_proxy_vars upper_proxy_vars other_proxy_vars

    # Define lowercase base variables needing case conversion
    lower_proxy_vars=(
        {http,https,ftp,rsync,socks,all,no}_proxy
        socat_proxy{,_port}
    )
    # Generate uppercase versions using zsh's (U) flag
    upper_proxy_vars=( ${(U)lower_proxy_vars} )

    # Other specific variables not needing case conversion
    other_proxy_vars=( GIT_PROXY_COMMAND )

    # Unset all collected variables
    unset $lower_proxy_vars $upper_proxy_vars $other_proxy_vars

    # Provide feedback to the user
    if (( ! quiet_mode )); then
        echo "Proxy environment variables cleared." >&2
    fi
}

# Sets HTTP/HTTPS proxy environment variables based on macOS System Preferences.
# Usage: proxy [quiet_mode]
#   quiet_mode: 0 = verbose (default), 1 = quiet
# Use proxy-socks to also enable SOCKS/FTP/socat/git proxy.
proxy () {
    local SOCAT_PROXY_WRAPPER="${${(%):-%x}:a:h}/socat-wrapper.sh"
    local quiet_mode=${1:-0}
    local http_only=${2:-1}

    # Fetch proxy settings ONCE
    local _scutil_output
    _scutil_output=$(/usr/sbin/scutil --proxy)
    if [[ -z "$_scutil_output" ]]; then
        return 1
    fi

    noproxy 1

    # --- Extract settings using zsh regex matching ---
    local _http_enabled=0 _http_server="" _http_port=""
    local _https_enabled=0 _https_server="" _https_port=""
    local _ftp_enabled=0 _ftp_server="" _ftp_port=""
    local _socks_enabled=0 _socks_server="" _socks_port=""
    local _no_proxy_str=""

    if [[ $_scutil_output =~ "HTTPEnable[[:space:]]*: 1" ]]; then
        _http_enabled=1
        [[ $_scutil_output =~ "HTTPProxy[[:space:]]*: ([^[:space:]]+)" ]] && _http_server=${match[1]}
        [[ $_scutil_output =~ "HTTPPort[[:space:]]*: ([0-9]+)" ]] && _http_port=${match[1]}
    fi

    if [[ $_scutil_output =~ "HTTPSEnable[[:space:]]*: 1" ]]; then
        _https_enabled=1
        [[ $_scutil_output =~ "HTTPSProxy[[:space:]]*: ([^[:space:]]+)" ]] && _https_server=${match[1]}
        [[ $_scutil_output =~ "HTTPSPort[[:space:]]*: ([0-9]+)" ]] && _https_port=${match[1]}
    fi

    if (( ! http_only )); then
        if [[ $_scutil_output =~ "FTPEnable[[:space:]]*: 1" ]]; then
            _ftp_enabled=1
            [[ $_scutil_output =~ "FTPProxy[[:space:]]*: ([^[:space:]]+)" ]] && _ftp_server=${match[1]}
            [[ $_scutil_output =~ "FTPPort[[:space:]]*: ([0-9]+)" ]] && _ftp_port=${match[1]}
        fi

        if [[ $_scutil_output =~ "SOCKSEnable[[:space:]]*: 1" ]]; then
            _socks_enabled=1
            [[ $_scutil_output =~ "SOCKSProxy[[:space:]]*: ([^[:space:]]+)" ]] && _socks_server=${match[1]}
            [[ $_scutil_output =~ "SOCKSPort[[:space:]]*: ([0-9]+)" ]] && _socks_port=${match[1]}
        fi
    fi

    # Exceptions (no_proxy)
    local -a _raw_exceptions=() _clean_exceptions=()
    if [[ $_scutil_output =~ 'ExceptionsList[[:space:]]*:[^{]*\{([^}]+)\}' ]]; then
        _raw_exceptions=( ${(f)match[1]} )
        local line
        for line in "${_raw_exceptions[@]}"; do
            line=$(echo "$line" | awk -F ':' '{ idx=index($0,":"); if(idx>0) print substr($0,idx+1) }' | sed 's/^[[:space:]]*//')
            line=${(LR)line}
            [[ -n "$line" ]] && _clean_exceptions+=("$line")
        done
        _no_proxy_str=${(j:,:)_clean_exceptions}
    fi

    local _primary_set=0 _rsync_proxy_set=0

    # 1. SOCKS (Highest Priority for all_proxy/socat/git)
    if [[ $_socks_enabled -eq 1 && -n "$_socks_server" && -n "$_socks_port" ]]; then
        export socks_proxy="socks5://${_socks_server}:${_socks_port}"
        export SOCKS_PROXY="$socks_proxy"
        export all_proxy="$socks_proxy"
        export ALL_PROXY="$all_proxy"
        export socat_proxy="SOCKS5-CONNECT:${_socks_server}"
        export socat_proxy_port="socksport=${_socks_port}"
        export SOCAT_PROXY="${socat_proxy}"
        export SOCAT_PROXY_PORT="${socat_proxy_port}"
        [[ -x "$SOCAT_PROXY_WRAPPER" ]] && export GIT_PROXY_COMMAND="${SOCAT_PROXY_WRAPPER}"
        _primary_set=1
        if (( ! quiet_mode )); then
            echo "Setting SOCKS proxy: ${socks_proxy}" >&2
        fi
    fi

    # 2. HTTPS (Second Priority for all_proxy, Highest for rsync_proxy)
    if [[ $_https_enabled -eq 1 && -n "$_https_server" && -n "$_https_port" ]]; then
        export https_proxy="http://${_https_server}:${_https_port}"
        export HTTPS_PROXY="$https_proxy"
        export rsync_proxy="${_https_server}:${_https_port}"
        export RSYNC_PROXY="$rsync_proxy"
        _rsync_proxy_set=1

        if (( ! quiet_mode )); then
            if (( _primary_set )); then
                echo "Setting HTTPS proxy: ${https_proxy} (Also available)" >&2
            else
                echo "Setting HTTPS proxy: ${https_proxy} (Primary)" >&2
            fi
            echo "Setting RSYNC proxy: ${rsync_proxy}" >&2
        fi

        if (( ! _primary_set )); then
            export all_proxy="$https_proxy"
            export ALL_PROXY="$all_proxy"
            if (( ! http_only )); then
                export socat_proxy="PROXY:${_https_server}"
                export socat_proxy_port="proxyport=${_https_port}"
                export SOCAT_PROXY="${socat_proxy}"
                export SOCAT_PROXY_PORT="${socat_proxy_port}"
                [[ -x "$SOCAT_PROXY_WRAPPER" ]] && export GIT_PROXY_COMMAND="${SOCAT_PROXY_WRAPPER}"
            fi
            _primary_set=1
        fi
    fi

    # 3. HTTP (Third Priority for all_proxy, Second for rsync_proxy)
    if [[ $_http_enabled -eq 1 && -n "$_http_server" && -n "$_http_port" ]]; then
        export http_proxy="http://${_http_server}:${_http_port}"
        export HTTP_PROXY="$http_proxy"

        if (( ! _rsync_proxy_set )); then
            export rsync_proxy="${_http_server}:${_http_port}"
            export RSYNC_PROXY="$rsync_proxy"
            _rsync_proxy_set=1
            if (( ! quiet_mode )); then
                echo "Setting RSYNC proxy: ${rsync_proxy}" >&2
            fi
        fi

        if (( ! quiet_mode )); then
            if (( _primary_set )); then
                echo "Setting HTTP proxy: ${http_proxy} (Also available)" >&2
            else
                echo "Setting HTTP proxy: ${http_proxy} (Primary)" >&2
            fi
        fi

        if (( ! _primary_set )); then
            export all_proxy="$http_proxy"
            export ALL_PROXY="$all_proxy"
            _primary_set=1
        fi
    fi

    # 4. FTP (Lowest Priority)
    if [[ $_ftp_enabled -eq 1 && -n "$_ftp_server" && -n "$_ftp_port" ]]; then
        export ftp_proxy="http://${_ftp_server}:${_ftp_port}"
        export FTP_PROXY="$ftp_proxy"
        if (( ! quiet_mode )); then
            echo "Setting FTP proxy: ${ftp_proxy}" >&2
        fi
    fi

    if [[ -n "$_no_proxy_str" ]]; then
        export no_proxy="$_no_proxy_str"
        export NO_PROXY="$_no_proxy_str"
    fi

    if (( ! quiet_mode && ! _primary_set && ! _rsync_proxy_set && ! (_ftp_enabled && -n "$_ftp_server" && -n "$_ftp_port") )); then
        echo "No active proxy settings applied." >&2
    fi

    return 0
}

# Sets all proxy variables including SOCKS/FTP/socat/git in addition to HTTP/HTTPS.
# Usage: proxy-socks [quiet_mode]
#   quiet_mode: 0 = verbose (default), 1 = quiet
proxy-socks () {
    proxy ${1:-0} 0
}

# enable proxy env by default.
proxy 1
