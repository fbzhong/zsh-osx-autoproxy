#!/bin/bash

# socat wrapper script for Git/SSH etc.
# Connects directly for LAN IPs and hosts in NO_PROXY list, otherwise uses socat proxy env vars.

# --- Configuration ---
# Ensure socat is findable (adjust paths if necessary for your system)
export PATH=$PATH:/opt/homebrew/bin:/opt/local/bin:/usr/local/bin

# Default socat arguments (e.g., timeout)
SOCAT_ARGS="-T180"

# --- Argument Check ---
if [[ $# -ne 2 ]]; then
    echo "Usage: $(basename "$0") <target_host> <target_port>" >&2
    exit 1
fi
_target_host="$1"
_target_port="$2"

# --- Resolve Proxy Configuration ---
# Prefer SOCAT_PROXY over socat_proxy, etc.
_proxy_cmd="${SOCAT_PROXY:-${socat_proxy}}"
_proxy_port_opts="${SOCAT_PROXY_PORT:-${socat_proxy_port}}" # Should contain options like ",socksport=1080" or ",proxyport=8080"

# Check if a proxy command is actually configured (more than just "PROXY:" or "SOCKS5:")
_is_proxy_configured=0
if [[ -n "$_proxy_cmd" && "$_proxy_cmd" != "PROXY:" && "$_proxy_cmd" != "SOCKS4A:" && "$_proxy_cmd" != "SOCKS5:" ]]; then
    _is_proxy_configured=1
fi

# --- Check Bypass Conditions ---
_connect_direct=0

# 1. Check for non-public / internal IPs (connect directly if matched)
#    Covers standard private, loopback, link-local, CGNAT/mesh ranges for IPv4/IPv6.
if \
   # IPv4 Private Ranges (RFC1918)
   [[ "$_target_host" == 10.* ]] || \
   [[ "$_target_host" =~ ^172\.(1[6-9]|2[0-9]|3[01])\..* ]] || \
   [[ "$_target_host" == 192.168.* ]] || \
   \
   # IPv4 Loopback (RFC5735)
   [[ "$_target_host" == 127.* ]] || \
   \
   # IPv4 Link-Local (RFC3927)
   [[ "$_target_host" == 169.254.* ]] || \
   \
   # IPv6 Loopback (RFC4291)
   [[ "$_target_host" == "::1" ]] || \
   \
   # IPv6 Link-Local (RFC4291) - fe80::/10
   # Checks for prefixes fe8, fe9, fea, feb (case-insensitive)
   [[ "$_target_host" == fe[89aAbB]* ]] || \
   \
   # IPv6 Unique Local Addresses (ULA - RFC4193) - fc00::/7
   # Checks for prefixes fc or fd
   [[ "$_target_host" == fc* || "$_target_host" == fd* ]] || \
   \
   # Shared Address Space / CGNAT / Netbird / Tailscale (RFC6598) - 100.64.0.0/10
   [[ "$_target_host" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\..* ]] \
; then
    _connect_direct=1
    # echo "Debug: Detected Non-Public/Internal IP [$_target_host]. Connecting directly." >&2
fi

# 2. Check NO_PROXY list (only if not already connecting directly)
if [[ $_connect_direct -eq 0 && $_is_proxy_configured -eq 1 ]]; then
    _no_proxy_list="${NO_PROXY:-${no_proxy}}"
    # echo "Debug: Checking against NO_PROXY list [$_no_proxy_list]" >&2

    # Handle '*' wildcard for bypassing everything
    if [[ "$_no_proxy_list" == "*" ]]; then
        _connect_direct=1
        # echo "Debug: NO_PROXY is '*'. Connecting directly." >&2
    elif [[ -n "$_no_proxy_list" ]]; then
        # Save IFS, set to comma, split into array, restore IFS
        OLD_IFS="$IFS"
        IFS=',' read -r -a no_proxy_items <<< "$_no_proxy_list"
        IFS="$OLD_IFS"

        for item in "${no_proxy_items[@]}"; do
            # Trim leading/trailing whitespace from item (using parameter expansion)
            item="${item#"${item%%[![:space:]]*}"}" # remove leading whitespace characters
            item="${item%"${item##*[![:space:]]}"}" # remove trailing whitespace characters

            if [[ -z "$item" ]]; then continue; fi

            # echo "Debug: Checking NO_PROXY item [$item] against [$_target_host]" >&2

            # Check for exact match
            if [[ "$_target_host" == "$item" ]]; then
                _connect_direct=1
                # echo "Debug: Matched NO_PROXY (exact) [$item]. Connecting directly." >&2
                break
            fi

            # Check for suffix match (handles ".domain" or "*.domain")
            # Ensure item starts with . or * and pattern matches end of host
            if [[ "$item" == .* || "$item" == \** ]]; then
                 # Remove leading . or *. for suffix check
                 suffix_pattern="${item#.}"
                 suffix_pattern="${suffix_pattern#\*.}"
                 if [[ -n "$suffix_pattern" && "$_target_host" == *".$suffix_pattern" ]]; then
                      _connect_direct=1
                      # echo "Debug: Matched NO_PROXY (suffix) [$item]. Connecting directly." >&2
                      break
                 fi
            fi

            # Note: IP/CIDR checks are more complex and omitted here for simplicity in bash.
        done
    fi
fi

# 3. Connect directly if no valid proxy is configured
if [[ $_is_proxy_configured -eq 0 ]]; then
     _connect_direct=1
     # echo "Debug: No valid proxy configured. Connecting directly." >&2
fi

# --- Execute Socat ---
exit_code=0
if [[ $_connect_direct -eq 1 ]]; then
    # echo "Info: Connecting directly to $_target_host:$_target_port" >&2
    socat $SOCAT_ARGS - "TCP-CONNECT:$_target_host:$_target_port"
    exit_code=$?
else
    # echo "Info: Connecting via proxy [$_proxy_cmd] to $_target_host:$_target_port" >&2
    # Assumes _proxy_port_opts contains the comma and option, e.g., ",socksport=1080"
    # Adds retry only for proxy connections
    socat $SOCAT_ARGS - "${_proxy_cmd}:${_target_host}:${_target_port},${_proxy_port_opts},retry=3"
    exit_code=$?
fi

exit $exit_code
