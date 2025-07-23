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

# Optimized function to set proxy environment variables based on macOS System Preferences
# Fetches settings using 'scutil --proxy' and applies a priority: SOCKS > HTTPS > HTTP
proxy () {
    # Define the path to the socat wrapper script relative to this script's location
    # Using 'local' makes SOCAT_PROXY_WRAPPER local to the function's scope.
    # If it needs to be globally available *before* calling proxy(), define it outside.
    local SOCAT_PROXY_WRAPPER="${${(%):-%x}:a:h}/socat-wrapper.sh" # Get dir of the script containing this function
    local quiet_mode=${1:-0} # 0 = verbose (default), 1 = quiet

    # Fetch proxy settings ONCE
    local _scutil_output
    _scutil_output=$(/usr/sbin/scutil --proxy)
    if [[ -z "$_scutil_output" ]]; then
        # echo "Warning: 'scutil --proxy' returned no output." >&2 # Optional warning
        # Ensure proxies are unset if scutil fails or returns empty
        return 1
    fi

    # Unset all proxy variables first (using your noproxy function) to start clean
    noproxy 1

    # --- Local variables to store extracted settings ---
    local _http_enabled=0 _http_server="" _http_port=""
    local _https_enabled=0 _https_server="" _https_port=""
    local _ftp_enabled=0 _ftp_server="" _ftp_port=""
    local _socks_enabled=0 _socks_server="" _socks_port=""
    local -a _exceptions=() # Array for no_proxy hosts
    local _no_proxy_str=""  # Comma-separated string

    # --- Extract settings using zsh regex matching ---
    # Note: Adjust regex if scutil output format differs significantly on your system

    # HTTP Proxy
    if [[ $_scutil_output =~ "HTTPEnable[[:space:]]*: 1" ]]; then
        _http_enabled=1
        [[ $_scutil_output =~ "HTTPProxy[[:space:]]*: ([^[:space:]]+)" ]] && _http_server=${match[1]}
        [[ $_scutil_output =~ "HTTPPort[[:space:]]*: ([0-9]+)" ]] && _http_port=${match[1]}
    fi

    # HTTPS Proxy
    if [[ $_scutil_output =~ "HTTPSEnable[[:space:]]*: 1" ]]; then
        _https_enabled=1
        [[ $_scutil_output =~ "HTTPSProxy[[:space:]]*: ([^[:space:]]+)" ]] && _https_server=${match[1]}
        [[ $_scutil_output =~ "HTTPSPort[[:space:]]*: ([0-9]+)" ]] && _https_port=${match[1]}
    fi

    # FTP Proxy (Less common nowadays, but kept for consistency)
    if [[ $_scutil_output =~ "FTPEnable[[:space:]]*: 1" ]]; then # Note: scutil might use FTPEnable, not FTPSEnable
        _ftp_enabled=1
        [[ $_scutil_output =~ "FTPProxy[[:space:]]*: ([^[:space:]]+)" ]] && _ftp_server=${match[1]}
        [[ $_scutil_output =~ "FTPPort[[:space:]]*: ([0-9]+)" ]] && _ftp_port=${match[1]}
    fi

    # SOCKS Proxy
    if [[ $_scutil_output =~ "SOCKSEnable[[:space:]]*: 1" ]]; then
        _socks_enabled=1
        [[ $_scutil_output =~ "SOCKSProxy[[:space:]]*: ([^[:space:]]+)" ]] && _socks_server=${match[1]}
        [[ $_scutil_output =~ "SOCKSPort[[:space:]]*: ([0-9]+)" ]] && _socks_port=${match[1]}
    fi

    # Exceptions (no_proxy) - Revised prefix removal
    local -a _raw_exceptions=() _clean_exceptions=()
    if [[ $_scutil_output =~ 'ExceptionsList[[:space:]]*:[^{]*\{([^}]+)\}' ]]; then
       _raw_exceptions=( ${(f)match[1]} ) # Split captured block into lines
       local line
       for line in "${_raw_exceptions[@]}"; do
           # Use awk/sed pipeline for robust prefix removal
           line=$(echo "$line" | awk -F ':' '{ idx=index($0,":"); if(idx>0) print substr($0,idx+1) }' | sed 's/^[[:space:]]*//')
           # Trim leading/trailing whitespace correctly (still useful for trailing whitespace)
           line=${(LR)line}
           # Add to clean list if not empty
           [[ -n "$line" ]] && _clean_exceptions+=("$line")
       done
       _no_proxy_str=${(j:,:)_clean_exceptions} # Join with commas
    fi

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

        # Set rsync_proxy if HTTPS is enabled (takes priority over HTTP for rsync)
        local _https_address="${_https_server}:${_https_port}"
        export rsync_proxy="$_https_address"
        export RSYNC_PROXY="$rsync_proxy"
        _rsync_proxy_set=1 # Mark rsync_proxy as set

        if (( ! quiet_mode )); then
            # Avoid printing if SOCKS is already set, unless verbose mode is needed
            if [[ $_primary_set -eq 0 ]]; then
                 echo "Setting HTTPS proxy: ${https_proxy} (Primary)" >&2
            else
                 echo "Setting HTTPS proxy: ${https_proxy} (Also available)" >&2
            fi
             echo "Setting RSYNC proxy: ${rsync_proxy}" >&2
        fi

        # Set general proxies ONLY if SOCKS didn't already set them
        if (( ! _primary_set )); then
            export all_proxy="$https_proxy"
            export ALL_PROXY="$all_proxy"
            export socat_proxy="PROXY:${_https_server}"
            export socat_proxy_port="proxyport=${_https_port}"
            export SOCAT_PROXY="${socat_proxy}"
            export SOCAT_PROXY_PORT="${socat_proxy_port}"
            [[ -x "$SOCAT_PROXY_WRAPPER" ]] && export GIT_PROXY_COMMAND="${SOCAT_PROXY_WRAPPER}"
            _primary_set=1
        fi
    fi

    # 3. HTTP (Third Priority for all_proxy, Second for rsync_proxy)
    if [[ $_http_enabled -eq 1 && -n "$_http_server" && -n "$_http_port" ]]; then
        export http_proxy="http://${_http_server}:${_http_port}"
        export HTTP_PROXY="$http_proxy"

        # Set rsync_proxy ONLY if HTTPS didn't already set it
        if (( ! _rsync_proxy_set )); then
             local _http_address="${_http_server}:${_http_port}"
             export rsync_proxy="$_http_address"
             export RSYNC_PROXY="$rsync_proxy"
             _rsync_proxy_set=1 # Mark as set

            if (( ! quiet_mode )); then
                 echo "Setting RSYNC proxy: ${rsync_proxy}" >&2
             fi
        fi

        if (( ! quiet_mode )); then
             if [[ $_primary_set -eq 0 ]]; then
                 echo "Setting HTTP proxy: ${http_proxy} (Primary)" >&2
            else
                 echo "Setting HTTP proxy: ${http_proxy} (Also available)" >&2
            fi
        fi

        # Set general proxies ONLY if neither SOCKS nor HTTPS set them
        if (( ! _primary_set )); then
            export all_proxy="$http_proxy"
            export ALL_PROXY="$all_proxy"
            # Typically no separate socat/git settings for plain HTTP proxy
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

    # Export NO_PROXY
    if [[ -n "$_no_proxy_str" ]]; then
        export no_proxy="$_no_proxy_str"
        export NO_PROXY="$_no_proxy_str"
    fi

    # Final check if any proxy was set at all
    if (( ! quiet_mode && ! _primary_set && ! _rsync_proxy_set && ! ($_ftp_enabled && -n "$_ftp_server" && -n "$_ftp_port") )); then
         echo "No active proxy settings applied." >&2
    fi

    return 0
}

# enable proxy env by default.
proxy 1
