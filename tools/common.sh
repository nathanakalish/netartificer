#!/bin/bash
# common.sh - shared helper functions for NetArtificer

# Get LLDP info from the local interface, try to auto-detect switch details
get_lldp_info() {
    local lldp_info lldp_name lldp_ip lldp_port lldp_vendor
    lldp_info=$(lldpctl 2>/dev/null)
    lldp_name=$(echo "$lldp_info" | grep -i "SysName" | head -n1 | awk -F': ' '{print $2}' | xargs)
    lldp_ip=$(echo "$lldp_info" | grep -i "MgmtIP" | head -n1 | awk -F': ' '{print $2}' | xargs)
    lldp_port=$(echo "$lldp_info" | grep -i "PortDescr" | head -n1 | awk -F': ' '{print $2}' | xargs)
    lldp_vendor=$(echo "$lldp_info" | grep -i "SysDescr" | awk -F': ' '{print $2}' | grep -i -E "Cisco|Aruba|Netgear" | head -n1 | awk '{print $1}')
    echo "$lldp_name|$lldp_ip|$lldp_port|$lldp_vendor"
}

# Validate an IPv4 address format
valid_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# Validate supported vendors
valid_vendor() {
    [[ $1 =~ ^(Cisco|Aruba|Netgear)$ ]]
}

# Validate interface port format (e.g. 1/1/29 or 29)
valid_port() {
    [[ $1 =~ ^([0-9]+(/[0-9]+){0,2})$ ]]
}

# Convert plain number port to Aruba style 1/1/XX
format_port() {
    [[ $1 =~ "/" ]] && echo "$1" || echo "1/1/$1"
}

# Check if a port falls within a range
port_in_range() {
    local port="$1"; local start="$2"; local end="$3"
    local p=$(echo "$port" | awk -F'/' '{print $NF}')
    local s=$(echo "$start" | awk -F'/' '{print $NF}')
    local e=$(echo "$end" | awk -F'/' '{print $NF}')
    [[ $p -ge $s && $p -le $e ]]
}

# Generic banner used by cable_test and switch_vlan
print_switch_banner() {
    show_banner
    [[ -n "$1" ]] && detected_name="$1"
    [[ -n "$2" ]] && detected_ip="$2"
    [[ -n "$3" ]] && detected_port="$3"
    [[ -n "$4" ]] && detected_vendor="$4"
    [ -n "$detected_name" ] && echo -e "${BLUE}Switch Name:${NC} $detected_name"
    [ -n "$detected_ip" ] && echo -e "${BLUE}Management IP:${NC} $detected_ip"
    [ -n "$detected_port" ] && echo -e "${BLUE}Connected Port:${NC} $detected_port"
    [ -n "$detected_vendor" ] && echo -e "${BLUE}Vendor:${NC} $detected_vendor"
    echo
}

# Export functions when sourced
export -f get_lldp_info valid_ip valid_vendor valid_port format_port port_in_range print_switch_banner
