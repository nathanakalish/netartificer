#!/bin/bash
# access_point.sh - Access Point control for NetArtificer

# Uses: LOGGING, LOG_FILE, show_banner, log, AP_SSID, AP_PASSPHRASE, etc. from main script
AP_STATUS_FILE="/tmp/netartificer_ap_status"
WLAN_IFACE="wlan0"
ETH_IFACE="eth0"
HOSTAPD_CONF="/tmp/hostapd.conf"

# Helper: Write status to file
set_ap_status() {
    # $1 = status, $2 = pid (optional)
    if [ "$1" = "running" ] && [ -n "$2" ]; then
        echo "status=running" > "$AP_STATUS_FILE"
        echo "pid=$2" >> "$AP_STATUS_FILE"
    else
        echo "status=not_running" > "$AP_STATUS_FILE"
        echo "pid=" >> "$AP_STATUS_FILE"
    fi
}

get_ap_status() {
    if [ -f "$AP_STATUS_FILE" ]; then
        grep '^status=' "$AP_STATUS_FILE" | cut -d'=' -f2
    else
        echo "not_running"
    fi
}

get_ap_pid() {
    if [ -f "$AP_STATUS_FILE" ]; then
        grep '^pid=' "$AP_STATUS_FILE" | cut -d'=' -f2
    fi
}

enable_ap() {
    show_banner
    # Interface config file for persistence
    AP_IFACES_FILE="/tmp/netartificer_ap_ifaces"
    # Load previous ifaces if available
    if [ -f "$AP_IFACES_FILE" ]; then
        source "$AP_IFACES_FILE"
    fi
    # List interfaces (excluding lo and tailscale)
    get_ifaces() {
        ip -o link show | awk -F': ' '{print $2}' | grep -vE '^(lo|tailscale[0-9]+|utun[0-9]+)$'
    }
    all_ifaces=( $(get_ifaces) )
    # Prompt for wired interface
    while true; do
        show_banner
        echo -e "${BLUE}Available interfaces:${NC}"
        for iface in "${all_ifaces[@]}"; do
            echo "  $iface"
        done
        read -e -rp "Enter wired interface [default: ${ETH_IFACE:-eth0}]: " input_eth
        [[ "$input_eth" == "qq" ]] && return
        [[ -z "$input_eth" ]] && input_eth="${ETH_IFACE:-eth0}"
        if [[ " ${all_ifaces[*]} " =~ " $input_eth " ]]; then
            ETH_IFACE="$input_eth"
            break
        else
            echo -e "${RED}Interface '$input_eth' not found. Try again or enter qq to quit.${NC}"
            sleep 3
        fi
    done
    # Remove selected wired iface from list for wireless selection
    avail_wl_ifaces=()
    for iface in "${all_ifaces[@]}"; do
        [[ "$iface" != "$ETH_IFACE" ]] && avail_wl_ifaces+=("$iface")
    done
    # Prompt for wireless interface
    while true; do
        show_banner
        echo -e "${BLUE}Available interfaces:${NC}"
        for iface in "${avail_wl_ifaces[@]}"; do
            echo "  $iface"
        done
        read -e -rp "Enter wireless interface [default: ${WLAN_IFACE:-wlan0}]: " input_wlan
        [[ "$input_wlan" == "qq" ]] && return
        [[ -z "$input_wlan" ]] && input_wlan="${WLAN_IFACE:-wlan0}"
        if [[ " ${avail_wl_ifaces[*]} " =~ " $input_wlan " ]]; then
            WLAN_IFACE="$input_wlan"
            break
        else
            echo -e "${RED}Interface '$input_wlan' not found or already selected as wired. Try again or enter qq to quit.${NC}"
            sleep 3
        fi
    done
    # Save selected interfaces for next run
    echo "ETH_IFACE=\"$ETH_IFACE\"" > "$AP_IFACES_FILE"
    echo "WLAN_IFACE=\"$WLAN_IFACE\"" >> "$AP_IFACES_FILE"
    SSID="${AP_SSID:-NetArtificer}"
    PASSPHRASE="${AP_PASSPHRASE:-changeme123}"
    # Bring interfaces up
    sudo ip link set "$WLAN_IFACE" down > /dev/null 2>&1
    sudo iw "$WLAN_IFACE" set type __ap > /dev/null 2>&1
    sudo ip link set "$WLAN_IFACE" up > /dev/null 2>&1
    # Enable IP forwarding
    sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1
    # Bridge eth0 and wlan0
    sudo brctl addbr br0 > /dev/null 2>&1
    sudo brctl addif br0 "$ETH_IFACE" > /dev/null 2>&1
    sudo brctl addif br0 "$WLAN_IFACE" > /dev/null 2>&1
    # Save current eth0 IP info
    ETH_IP=$(ip -4 addr show "$ETH_IFACE" | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}/\\d+')
    ETH_GW=$(ip route | grep default | grep "$ETH_IFACE" | awk '{print $3}')
    # Move IP config to bridge
    # Save current eth0 IP info
    ETH_IP=$(ip -4 addr show "$ETH_IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')
    ETH_GW=$(ip route | grep default | grep "$ETH_IFACE" | awk '{print $3}')

    # Move IP config to bridge
    sudo ip addr flush dev "$ETH_IFACE"
    sudo ip link set "$ETH_IFACE" up
    sudo ip link set "$WLAN_IFACE" up

    sudo ip link set br0 up
    sudo ip addr add "$ETH_IP" dev br0
    sudo ip route add default via "$ETH_GW"

    sudo ip link set br0 up > /dev/null 2>&1
    sudo brctl stp br0 off > /dev/null 2>&1
    sudo ip link set "$WLAN_IFACE" promisc on > /dev/null 2>&1
    sudo iw dev "$WLAN_IFACE" set power_save off > /dev/null 2>&1
    sudo ip addr add "$ETH_IP" dev br0 > /dev/null 2>&1
    sudo ip route add default via "$ETH_GW" > /dev/null 2>&1
    # Create hostapd config
    cat <<EOF | sudo tee "$HOSTAPD_CONF" > /dev/null
interface=$WLAN_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
bridge=br0
EOF
    # Start hostapd
    show_banner
    echo -e "${GREEN}Starting access point '$SSID'...${NC}"
    sudo hostapd "$HOSTAPD_CONF" > /dev/null 2>&1 &
    HAPID=$!
    set_ap_status running $HAPID
    log "Access Point enabled (SSID: $SSID, PID: $HAPID)"
}

disable_ap() {
    show_banner
    echo -e "${BLUE}Disabling Access Point...${NC}"
    HAPID=$(get_ap_pid)
    if [ -n "$HAPID" ]; then
        sudo kill $HAPID > /dev/null 2>&1
        wait $HAPID 2>/dev/null || true
    fi
    sudo ip link set br0 down > /dev/null 2>&1
    sudo ip link set "$WLAN_IFACE" promisc off > /dev/null 2>&1
    sudo iw dev "$WLAN_IFACE" set power_save on > /dev/null 2>&1
    sudo ip link set "$ETH_IFACE" down > /dev/null 2>&1
    sudo ip link set "$ETH_IFACE" up > /dev/null 2>&1
    if pidof dhcpcd > /dev/null 2>&1; then
        sudo dhcpcd "$ETH_IFACE" --rebind > /dev/null 2>&1
    fi
    sudo brctl delbr br0 > /dev/null 2>&1
    sudo ip link set "$WLAN_IFACE" down > /dev/null 2>&1
    sudo iw "$WLAN_IFACE" set type managed > /dev/null 2>&1
    sudo ip link set "$WLAN_IFACE" up > /dev/null 2>&1
    set_ap_status not_running
    log "Access Point disabled."
}

# Export for main script
export -f enable_ap
default_ap_exports=(disable_ap set_ap_status get_ap_status get_ap_pid)
for fn in "${default_ap_exports[@]}"; do
    export -f "$fn"
done
