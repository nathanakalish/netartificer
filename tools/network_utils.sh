#!/bin/bash
# network_utils.sh - Handy network tools and helpers

# display_interfaces: Show all active IPv4 interfaces (except loopback and Tailscale/utun)
display_interfaces() {
    shown_br0=0
    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show up | awk '!/ lo / && !($2 ~ /^tailscale[0-9]+$/) && !($2 ~ /^utun[0-9]+$/) {split($4, a, "/"); print $2, a[1]}' | while read -r iface ipaddr; do
            ap_label=""
            if [ -d "/sys/class/net/$iface/wireless" ] || iw dev "$iface" info >/dev/null 2>&1; then
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mWi-Fi\033[0m)%s\n" "$iface" "$ipaddr" "$ap_label"
            else
                speed="Unknown"
                if command -v ethtool >/dev/null 2>&1; then
                    speed=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}')
                fi
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mEthernet\033[0m, \033[0;36m%s\033[0m)%s\n" "$iface" "$ipaddr" "$speed" "$ap_label"
            fi
        done
        # If br0 exists, show it and the bridged interfaces in the requested format
        if ip link show br0 >/dev/null 2>&1; then
            br0_ip=$(ip -4 addr show br0 | awk '/inet / {print $2}' | cut -d'/' -f1)
            [ -z "$br0_ip" ] && br0_ip="No IP"
            #printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mAccess Point Bridge\033[0m)\n" "br0" "$br0_ip"
            if ip link show eth0 >/dev/null 2>&1; then
                printf "\033[0;36meth0\033[0m - \033[0;32mBridged \033[0m(\033[0;36mbr0 Source\033[0m)\n"
            fi
            if ip link show wlan0 >/dev/null 2>&1; then
                printf "\033[0;36mwlan0\033[0m - \033[0;32mBridged \033[0m(\033[0;36mbr0 Broadcast\033[0m)\n"
            fi
        fi
    elif command -v ifconfig >/dev/null 2>&1; then
        wifi_ifaces=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/ {getline; print $2}')
        ifconfig | awk '/flags=.*UP/ {iface=$1} /inet / && iface!="lo0:" && iface!~"^tailscale[0-9]+:" && iface!~"^utun[0-9]+:" {split($2, a, ":"); print iface, $2}' | while read -r iface ipaddr; do
            iface_clean=$(echo "$iface" | sed 's/://')
            ap_label=""
            if echo "$wifi_ifaces" | grep -wq "$iface_clean"; then
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mWi-Fi\033[0m)%s\n" "$iface_clean" "$ipaddr" "$ap_label"
            else
                speed=$(ifconfig "$iface_clean" 2>/dev/null | awk -F': ' '/media: / {print $2}' | awk '{print $2}' | head -n1)
                [ -z "$speed" ] && speed="Unknown"
                speed=$(echo "$speed" | sed 's/^[(]*//;s/[)]*$//')
                if echo "$speed" | grep -Eq '^(100baseT|10baseT)'; then
                    speed_disp="\033[0;31m$speed\033[0m"
                else
                    speed_disp="$speed"
                fi
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mEthernet\033[0m, \033[0;36m%s\033[0m)%s\n" "$iface_clean" "$ipaddr" "$speed_disp" "$ap_label"
            fi
        done
        # If br0 exists, show it and the bridged interfaces in the requested format
        if ifconfig br0 >/dev/null 2>&1; then
            br0_ip=$(ifconfig br0 2>/dev/null | awk '/inet / {print $2}')
            [ -z "$br0_ip" ] && br0_ip="No IP"
            #printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mAccess Point Bridge\033[0m)\n" "br0" "$br0_ip"
            if ifconfig eth0 >/dev/null 2>&1; then
                printf "\033[0;36meth0\033[0m - \033[0;32mBridged \033[0m(\033[0;36mbr0 Source\033[0m)\n"
            fi
            if ifconfig wlan0 >/dev/null 2>&1; then
                printf "\033[0;36mwlan0\033[0m - \033[0;32mBridged \033[0m(\033[0;36mbr0 Broadcast\033[0m)\n"
            fi
        fi
    else
        echo -e "${RED}No supported command found to list interfaces.${NC}"
    fi
}

# display_lldp_info: Try to grab LLDP (switch) info if possible
display_lldp_info() {
    ap_was_running=0
    if command -v get_ap_status >/dev/null 2>&1; then
        if [ "$(get_ap_status)" = "running" ]; then
            ap_was_running=1
            echo -e "${YELLOW}Access Point is running. Temporarily disabling AP to gather LLDP info...${NC}"
            disable_ap
            echo -e "${YELLOW}Waiting for Access Point to stop...${NC}"
            sleep 3
        fi
    fi
    clear
    show_banner
    echo -e "${BLUE}Connected Switch Information:${NC}"
    if ! command -v lldpctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        echo -e "${RED}Unable to locate the lldpctl or jq command.${NC}"
        echo -e "${GREEN}Press any key to continue...${NC}"
        read -n 1 -s
        [ "$ap_was_running" -eq 1 ] && enable_ap
        return
    fi
    lldp_json=$(lldpctl -f json 2>/dev/null)
    if [ -z "$lldp_json" ]; then
        echo -e "${RED}No LLDP information found. Please ensure lldpd is running and LLDP is enabled on your switch.${NC}"
        read -n 1 -s
        [ "$ap_was_running" -eq 1 ] && enable_ap
        return
    fi
    HIDE_TAILSCALE_LLDP=${HIDE_TAILSCALE_LLDP:-disabled}
    # Helper to check if IP is in 100.64.0.0/10
    is_tailscale_ip() {
        ip=$1
        IFS=. read -r o1 o2 o3 o4 <<< "$ip"
        if [ "$o1" -eq 100 ] && [ "$o2" -ge 64 ] && [ "$o2" -le 127 ]; then
            return 0
        fi
        return 1
    }
    # Parse all neighbors (no --args/--named)
    neighbors=()
    while IFS= read -r neighbor; do
        neighbors+=("$neighbor")
    done < <(echo "$lldp_json" | jq -c '
        .lldp.interface | (if type=="array" then . else to_entries | map({(.key): .value}) end) |
        map(to_entries[] | . as $iface_entry |
            $iface_entry.value.chassis | to_entries[] |
            {iface: $iface_entry.key, chassis_name: .key, chassis: .value, port: $iface_entry.value.port, vlan: $iface_entry.value.vlan}
        ) | .[]
    ')
    tailscale_neighbors=()
    nontailscale_neighbors=()
    for neighbor in "${neighbors[@]}"; do
        mgmtips=$(echo "$neighbor" | jq -r '.chassis["mgmt-ip"] | if type=="array" then .[] else . end')
        is_tailscale=0
        for ip in $mgmtips; do
            if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                if is_tailscale_ip "$ip"; then
                    is_tailscale=1
                fi
            fi
        done
        if [ $is_tailscale -eq 1 ]; then
            tailscale_neighbors+=("$neighbor")
        else
            nontailscale_neighbors+=("$neighbor")
        fi
    done
    display_list=()
    if [ "$HIDE_TAILSCALE_LLDP" = "enabled" ]; then
        if [ ${#nontailscale_neighbors[@]} -eq 0 ]; then
            echo -e "${YELLOW}No non-Tailscale LLDP neighbors found. Only Tailscale neighbors are present.${NC}"
            echo -e "${GREEN}Press any key to return to the menu...${NC}"
            read -n 1 -s
            [ "$ap_was_running" -eq 1 ] && enable_ap
            return
        fi
        display_list=("${nontailscale_neighbors[@]}")
    else
        display_list=("${nontailscale_neighbors[@]}" "${tailscale_neighbors[@]}")
    fi
    total_neighbors=${#display_list[@]}
    if [ $total_neighbors -eq 0 ]; then
        echo -e "${YELLOW}No valid LLDP neighbors found.${NC}"
        echo -e "${GREEN}Press any key to return to the menu...${NC}"
        read -n 1 -s
        [ "$ap_was_running" -eq 1 ] && enable_ap
        return
    fi
    if [ $total_neighbors -eq 1 ]; then
        i=0
        show_neighbor=1
    else
        i=0
        show_neighbor=1
    fi
    while [ $show_neighbor -eq 1 ]; do
        neighbor_json="${display_list[$i]}"
        iface=$(echo "$neighbor_json" | jq -r '.iface')
        chassis_name=$(echo "$neighbor_json" | jq -r '.chassis_name')
        sysdescr=$(echo "$neighbor_json" | jq -r '.chassis.descr // "Unknown"')
        mgmtips=$(echo "$neighbor_json" | jq -r '.chassis["mgmt-ip"] | if type=="array" then .[] else . end')
        mgmtip4=""
        mgmtip6=""
        for ip in $mgmtips; do
            if [[ "$ip" == *:* ]]; then
                mgmtip6="$ip"
            elif [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                mgmtip4="$ip"
            fi
        done
        port_descr=$(echo "$neighbor_json" | jq -r '.port.descr // "Unknown"')
        link_speed=$(echo "$neighbor_json" | jq -r '.port["auto-negotiation"].current // "Unknown"')
        vlan_id=$(echo "$neighbor_json" | jq -r '.vlan["vlan-id"] // empty')
        vlan_name=$(echo "$neighbor_json" | jq -r '.vlan.value // empty')
        pvid=$(echo "$neighbor_json" | jq -r '.vlan.pvid // false')
        if [ -n "$vlan_id" ]; then
            if [ "$pvid" = "true" ]; then
                vlans="\033[0;32m$vlan_id${vlan_name:+ $vlan_name}\033[0m"
                has_pvid_vlan=1
            else
                vlans="$vlan_id${vlan_name:+ $vlan_name}"
                has_pvid_vlan=0
            fi
        else
            vlans="Unknown"
            has_pvid_vlan=0
        fi
        clear
        show_banner
        if [ $total_neighbors -gt 1 ]; then
            echo -e "${YELLOW}Multiple neighbors found. Showing $((i+1)) of $total_neighbors${NC}"
        fi
        echo -e "${BLUE}Local Interface:${NC} ${iface:-Unknown}"
        echo -e "${BLUE}Switch Name:${NC} ${chassis_name:-Unknown}"
        echo -e "${BLUE}Description:${NC} ${sysdescr:-Unknown}"
        if [ -n "$mgmtip4" ]; then
            echo -e "${BLUE}Management IP:${NC} ${mgmtip4}"
        fi
        if [ -n "$mgmtip6" ]; then
            echo -e "${BLUE}Management IPv6:${NC} ${mgmtip6}"
        fi
        echo -e "${BLUE}Connected Port:${NC} ${port_descr:-Unknown}"
        echo -e "${BLUE}Negotiated Link Speed:${NC} ${link_speed:-Unknown}"
        echo -e "${BLUE}VLAN(s):${NC} ${vlans:-Unknown}"
        if [ "$has_pvid_vlan" -eq 1 ]; then
            echo -e "${GREEN}Note:${NC} The VLAN in green is the PVID (untagged) VLAN."
        fi
        echo ""
        if [ $total_neighbors -eq 1 ]; then
            echo -e "${GREEN}Press any key to continue...${NC}"
            read -n 1 -s
            show_neighbor=0
        else
            prompt="[←] previous, [→] next, [q]uit: "
            if [ $i -eq 0 ]; then
                prompt="[→] next, [q]uit: "
            elif [ $i -eq $((total_neighbors-1)) ]; then
                prompt="[←] previous, [q]uit: "
            fi
            echo -ne "$prompt"
            IFS= read -rsn1 navkey
            if [[ $navkey == $'\e' ]]; then
                read -rsn2 navkey2
                navkey+=$navkey2
            fi
            echo
            case "$navkey" in
                $'\e[C') # right arrow
                    if [ $i -lt $((total_neighbors-1)) ]; then
                        i=$((i+1))
                    fi
                    ;;
                $'\e[D') # left arrow
                    if [ $i -gt 0 ]; then
                        i=$((i-1))
                    fi
                    ;;
                q|Q)
                    show_neighbor=0
                    ;;
                *)
                    # ignore other keys
                    ;;
            esac
        fi
    done
    [ "$ap_was_running" -eq 1 ] && enable_ap
    return
}

# display_arp_table: Print out the ARP table in a readable way
display_arp_table() {
    clear
    show_banner
    echo -e "${BLUE}ARP Table:${NC}"
    if command -v arp >/dev/null 2>&1; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            arp -an | column -t
        else
            arp -n | column -t
        fi
    else
        echo -e "${RED}arp command not found.${NC}"
    fi
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# ping_host: Ask for a host and keep pinging it until stopped
ping_host() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_host_msg" ] && echo -e "${RED}$invalid_host_msg${NC}"
        read -e -p $'\033[0;36mEnter the host to ping:\033[0m ' host
        [ "$host" = "qq" ] && return
        if [[ -n "$host" && "$host" =~ ^([a-zA-Z0-9.-]+)$ ]]; then
            invalid_host_msg=""
            break
        else
            clear
            show_banner
            invalid_host_msg="A valid host is required. Please try again."
        fi
    done
    echo -e "${BLUE}Pinging${NC} ${GREEN}$host${NC}... (Press Ctrl+C to stop)"
    ping "$host"
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# mtr_trace: Run an MTR trace to a host, with optional hostname resolution
mtr_trace() {
    show_banner
    while true; do
        [ -n "$invalid_host_msg" ] && echo -e "${RED}$invalid_host_msg${NC}"
        read -e -p $'\033[0;36mEnter host to trace:\033[0m ' host
        [ "$host" = "qq" ] && return
        if [[ -n "$host" && "$host" =~ ^([a-zA-Z0-9.-]+)$ ]]; then
            invalid_host_msg=""
            break
        else
            clear
            show_banner
            invalid_host_msg="No host provided or invalid format. Please try again."
        fi
    done
    show_banner
    while true; do
        read -e -p $'\033[0;36mDo you want to resolve IP addresses to hostnames? (y/n):\033[0m ' resolve_choice
        [ "$host" = "qq" ] && return
        case "$resolve_choice" in
            [Yy]*) resolve_flag=""; break ;;
            [Nn]*) resolve_flag="-n"; break ;;
            *) echo -e "${RED}Please enter 'y' or 'n'.${NC}" ;;
        esac
    done
    clear
    show_banner
    echo -e "${BLUE}Running trace on${NC} ${GREEN}$host${NC}..."
    log "Running trace on $host"
    mtr_output=$(mtr -r -c 5 $resolve_flag "$host")
    mtr_output=$(echo "$mtr_output" | sed '1d')
    sleep 1
    clear
    show_banner
    echo -e "${BLUE}Trace results for${NC} ${GREEN}$host${NC}:"
    echo "$mtr_output" | awk '
    BEGIN {
        YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m";
    }
    NR<=2 { print; next }
    {
        loss_col = 3;
        loss = $loss_col;
        gsub("%", "", loss);
        if (loss ~ /^([0-9]+\.[0-9]+|[0-9]+)$/) {
            loss_val = loss + 0;
            if (loss_val > 20) {
                print RED $0 NC;
            } else if (loss_val > 0) {
                print YELLOW $0 NC;
            } else {
                print $0;
            }
        } else {
            print $0;
        }
    }'
    echo ""
    echo "'???' indicates a host that is not responding to ICMP echo (ping) requests."
    echo "Otherwise, high packet loss may be due to ping rate limiting or network issues."
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# dns_lookup: Do a DNS lookup for a domain (using dig or nslookup)
dns_lookup() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_domain_msg" ] && echo -e "${RED}$invalid_domain_msg${NC}"
        read -e -p $'\033[0;36mEnter a domain for DNS lookup:\033[0m ' domain
        [ "$domain" = "qq" ] && return
        if [[ -n "$domain" && "$domain" =~ ^([a-zA-Z0-9.-]+)$ ]]; then
            invalid_domain_msg=""
            break
        else
            clear
            show_banner
            invalid_domain_msg="A domain is required. Please try again."
        fi
    done
    read -e -p $'\033[0;36mEnter the DNS server (or leave blank for the system\'s default):\033[0m ' dns_server
    [ "$dns_server" = "qq" ] && return
    if [ -n "$dns_server" ] && [[ ! "$dns_server" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${RED}Invalid DNS server IP. Using system default.${NC}"
        dns_server=""
    fi
    echo -e "${BLUE}Performing DNS lookup for${NC} ${GREEN}$domain${NC} using DNS server: ${GREEN}${dns_server:-system}${NC}"
    local result
    if command -v dig >/dev/null 2>&1; then
        if [ -n "$dns_server" ]; then
            result=$(dig +short @"$dns_server" "$domain")
        else
            result=$(dig +short "$domain")
        fi
    elif command -v nslookup >/dev/null 2>&1; then
        if [ -n "$dns_server" ]; then
            result=$(nslookup "$domain" "$dns_server" | awk '/^Address: / { print $2 }')
        else
            result=$(nslookup "$domain" | awk '/^Address: / { print $2 }')
        fi
    else
        echo -e "${RED}Neither dig nor nslookup is installed.${NC}"
        return 1
    fi
    echo "$result" | grep -v '^0\.0\.0\.0$' | sort -u
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# port_scan: Scan a host for open ports in a range (using nmap)
port_scan() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_host_msg" ] && echo -e "${RED}$invalid_host_msg${NC}"
        read -e -p $'\033[0;36mEnter the host to scan:\033[0m ' host
        [ "$host" = "qq" ] && return
        if [[ -n "$host" && "$host" =~ ^([a-zA-Z0-9.-]+)$ ]]; then
            invalid_host_msg=""
            break
        else
            clear
            show_banner
            invalid_host_msg="No host specified or invalid format. Please try again."
        fi
    done
    while true; do
        [ -n "$invalid_start_port_msg" ] && echo -e "${RED}$invalid_start_port_msg${NC}"
        read -e -p $'\033[0;36mEnter the start port:\033[0m ' start_port
        [ "$start_port" = "qq" ] && return
        if [[ "$start_port" =~ ^[0-9]+$ && $start_port -ge 1 && $start_port -le 65535 ]]; then
            invalid_start_port_msg=""
            break
        else
            clear
            show_banner
            invalid_start_port_msg="Invalid start port. Please enter a number between 1 and 65535."
        fi
    done
    while true; do
        [ -n "$invalid_end_port_msg" ] && echo -e "${RED}$invalid_end_port_msg${NC}"
        read -e -p $'\033[0;36mEnter the end port:\033[0m ' end_port
        [ "$end_port" = "qq" ] && return
        if [[ "$end_port" =~ ^[0-9]+$ && $end_port -ge $start_port && $end_port -le 65535 ]]; then
            invalid_end_port_msg=""
            break
        else
            clear
            show_banner
            invalid_end_port_msg="Invalid end port. Please enter a number between $start_port and 65535."
        fi
    done
    echo -e "${BLUE}Scanning ports $start_port to $end_port on${NC} ${GREEN}$host${NC} using nmap..."
    output=$(nmap -Pn -p ${start_port}-${end_port} -sV "$host")
    echo
    echo "$output" | awk 'BEGIN {
        OFS="";
        format = "\033[0;36m%-10s %-8s %-10s %s\033[0m\n";
        printf format, "PORT", "STATE", "SERVICE", "VERSION"
    }
    /open/ {
        printf "\033[0;32m%-10s %-8s %-10s %s\033[0m\n", $1, $2, $3, substr($0, index($0,$4))
    }'
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# wake_on_lan: Send a Wake-on-LAN packet after checking the MAC address
wake_on_lan() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_mac_msg" ] && echo -e "${RED}$invalid_mac_msg${NC}"
        read -e -p $'\033[0;36mEnter the MAC address:\033[0m ' mac
        [ "$mac" = "qq" ] && return
        if [ -z "$mac" ]; then
            clear
            show_banner
            invalid_mac_msg="A MAC address is required."
            continue
        fi
        raw_mac=$(echo "$mac" | tr -d ':-' | tr '[:lower:]' '[:upper:]')
        if [[ "$raw_mac" =~ ^[A-F0-9]{12}$ ]]; then
            invalid_mac_msg=""
            break
        else
            clear
            show_banner
            invalid_mac_msg="Invalid MAC address format. It must be 12 hexadecimal characters."
        fi
    done
    while true; do
        [ -n "$invalid_ip_msg" ] && echo -e "${RED}$invalid_ip_msg${NC}"
        read -e -p $'\033[0;36mEnter the target IP (default is broadcast):\033[0m ' ip
        [ "$ip" = "qq" ] && return
        [ -z "$ip" ] && ip="255.255.255.255"
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            invalid_ip_msg=""
            break
        elif [ "$ip" = "255.255.255.255" ]; then
            invalid_ip_msg=""
            break
        else
            clear
            show_banner
            invalid_ip_msg="Invalid IP address. Please try again."
        fi
    done
    while true; do
        [ -n "$invalid_port_msg" ] && echo -e "${RED}$invalid_port_msg${NC}"
        read -e -p $'\033[0;36mEnter the target port (default is 9):\033[0m ' port
        [ "$port" = "qq" ] && return
        [ -z "$port" ] && port="9"
        if [[ "$port" =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]; then
            invalid_port_msg=""
            break
        else
            clear
            show_banner
            invalid_port_msg="Invalid port. Please enter a number between 1 and 65535."
        fi
    done
    echo -e "${BLUE}Sending Wake-on-LAN packet to${NC} ${GREEN}${formatted_mac}${NC} using IP ${GREEN}$ip${NC} and port ${GREEN}$port${NC}..."
    wakeonlan -i "$ip" -p "$port" "$formatted_mac" > /dev/null 2>&1
    echo -e "${GREEN}Packet sent successfully.${NC}"
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# speed_test: Run a speed test with speedtest-cli and show the results
speed_test() {
    clear
    show_banner
    echo -e "${BLUE}Running network speed test...${NC}"
    if ! command -v speedtest-cli >/dev/null 2>&1; then
        echo -e "${RED}speedtest-cli is not installed.${NC}"
        return 1
    fi
    local output
    output=$(speedtest-cli 2>&1)
    local ip isp server ping download upload
    isp=$(echo "$output" | grep -oE 'Testing from .+ \(' | sed 's/Testing from //;s/ (//')
    ip=$(echo "$output" | grep -oE '\([0-9.]+\)' | head -n1 | tr -d '()')
    server=$(echo "$output" | grep -oE 'Hosted by .+\[[^]]+\]' | sed 's/Hosted by //')
    ping=$(echo "$output" | grep -oE 'Hosted by .+\[[^]]+\]: [0-9.]+ ms' | sed -E 's/.*: ([0-9.]+ ms)/\1/')
    download=$(echo "$output" | awk '/Download:/ {print $2, $3}')
    upload=$(echo "$output" | awk '/Upload:/ {print $2, $3}')
    [ -z "$ip" ] && ip="Unknown"
    [ -z "$isp" ] && isp="Unknown"
    [ -z "$server" ] && server="Unknown"
    [ -z "$ping" ] && ping="Unknown"
    [ -z "$download" ] && download="Unknown"
    [ -z "$upload" ] && upload="Unknown"
    echo -e "${BLUE}Your IP:${NC} ${GREEN}$ip ($isp)${NC}"
    echo -e "${BLUE}Testing server:${NC} ${GREEN}$server${NC}"
    echo -e "${BLUE}Ping:${NC} ${GREEN}$ping${NC}"
    echo -e "${BLUE}Download speed:${NC} ${GREEN}$download${NC}"
    echo -e "${BLUE}Upload speed:${NC} ${GREEN}$upload${NC}"
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# whois_lookup: Do a WHOIS lookup for a domain and highlight redacted info
whois_lookup() {
    clear
    show_banner
    read -e -p $'\033[0;36mEnter the domain for WHOIS lookup:\033[0m ' domain
    if [ -z "$domain" ]; then
        echo "A domain must be specified."
        return 1
    fi
    echo "Performing WHOIS lookup for $domain..."
    whois "$domain" | awk '/^Domain Name:/ {found=1} found'
    echo ""
    echo "Press any key to continue..."
    read -n 1 -s
}

# ping_sweep: Ping a whole subnet (CIDR) to see who's alive (using nmap)
ping_sweep() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_cidr_msg" ] && echo -e "${RED}$invalid_cidr_msg${NC}"
        read -e -p $'\033[0;36mEnter the CIDR for ping sweep (e.g., 192.168.1.0/24):\033[0m ' cidr
        [ "$cidr" = "qq" ] && return
        if [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]+)$ ]]; then
            invalid_cidr_msg=""
            break
        else
            clear
            show_banner
            invalid_cidr_msg="Invalid CIDR format. Please try again."
        fi
    done
    echo -e "${BLUE}Performing ping sweep on${NC} ${GREEN}$cidr${NC} using nmap..."
    term_width=$(tput cols)
    field_width=18
    cols=$(( term_width / field_width ))
    [ "$cols" -lt 1 ] && cols=1
    nmap -sn "$cidr" | awk '/Nmap scan report for/ {print $5}' | \
    awk -v BLUE="\033[0;36m" -v GREEN="\033[0;32m" -v NC="\033[0m" -v cols="$cols" '
        {
            ips[NR] = $1
        }
        END {
            for (i = 1; i <= NR; i++) {
                printf BLUE "|" NC
                printf GREEN "%-16s" NC, ips[i]
                if (i % cols == 0) {
                    printf BLUE "|" NC "\n"
                }
            }
            if ((NR % cols) != 0) {
                printf BLUE "|" NC "\n"
            }
        }'
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# snmp_monitor: Query a host for an SNMP OID (default: system description)
snmp_monitor() {
    clear
    show_banner
    while true; do
        [ -n "$invalid_host_msg" ] && echo -e "${RED}$invalid_host_msg${NC}"
        echo -e "${BLUE}Enter host for SNMP monitoring:${NC}"
        read -e -rp "Host: " host
        [ "$host" = "qq" ] && return
        if [[ -n "$host" && "$host" =~ ^([a-zA-Z0-9.-]+)$ ]]; then
            invalid_host_msg=""
            break
        else
            clear
            show_banner
            invalid_host_msg="No host provided or invalid format. Please try again."
        fi
    done
    echo -e "${BLUE}Enter SNMP OID (or leave empty for default system OID):${NC}"
    read -e -rp "OID: " oid
    [ "$oid" = "qq" ] && return
    if [ -z "$oid" ]; then
        oid="1.3.6.1.2.1.1.1.0"
    fi
    echo -e "${BLUE}Querying SNMP for $host (OID: $oid)...${NC}"
    log "SNMP monitoring for $host OID $oid"
    snmpget -v2c -c public "$host" "$oid"
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
}

# log: Write a message to the log file if logging is on
log() {
    if [ "${LOGGING:-enabled}" = "enabled" ]; then
        local message="$1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}
