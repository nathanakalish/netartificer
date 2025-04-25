#!/bin/bash
# network_utils.sh - Handy network tools and helpers

# display_interfaces: Show all active IPv4 interfaces (except loopback and Tailscale/utun)
display_interfaces() {
    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show up | awk '!/ lo / && !($2 ~ /^tailscale[0-9]+$/) && !($2 ~ /^utun[0-9]+$/) {
            split($4, a, "/");
            print $2, a[1]
        }' | while read -r iface ipaddr; do
            if [ -d "/sys/class/net/$iface/wireless" ] || iw dev "$iface" info >/dev/null 2>&1; then
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mWi-Fi\033[0m)\n" "$iface" "$ipaddr"
            else
                speed="Unknown"
                if command -v ethtool >/dev/null 2>&1; then
                    speed=$(ethtool "$iface" 2>/dev/null | awk -F': ' '/Speed:/ {print $2}')
                fi
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mEthernet\033[0m, \033[0;36m%s\033[0m)\n" "$iface" "$ipaddr" "$speed"
            fi
        done
    elif command -v ifconfig >/dev/null 2>&1; then
        wifi_ifaces=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi|AirPort/ {getline; print $2}')
        ifconfig | awk '/flags=.*UP/ {iface=$1} /inet / && iface!="lo0:" && iface!~"^tailscale[0-9]+:" && iface!~"^utun[0-9]+:" {
            split($2, a, ":");
            print iface, $2
        }' | while read -r iface ipaddr; do
            iface_clean=$(echo "$iface" | sed 's/://')
            if echo "$wifi_ifaces" | grep -wq "$iface_clean"; then
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mWi-Fi\033[0m)\n" "$iface_clean" "$ipaddr"
            else
                speed=$(ifconfig "$iface_clean" 2>/dev/null | awk -F': ' '/media: / {print $2}' | awk '{print $2}' | head -n1)
                [ -z "$speed" ] && speed="Unknown"
                speed=$(echo "$speed" | sed 's/^[(]*//;s/[)]*$//')
                if echo "$speed" | grep -Eq '^(100baseT|10baseT)'; then
                    speed_disp="\033[0;31m$speed\033[0m"
                else
                    speed_disp="$speed"
                fi
                printf "\033[0;36m%s\033[0m - \033[0;32m%s\033[0m (\033[0;36mEthernet\033[0m, \033[0;36m%s\033[0m)\n" "$iface_clean" "$ipaddr" "$speed_disp"
            fi
        done
    else
        echo -e "${RED}No supported command found to list interfaces.${NC}"
    fi
}

# display_lldp_info: Try to grab LLDP (switch) info if possible
display_lldp_info() {
    clear
    show_banner
    echo -e "${BLUE}Connected Switch Information:${NC}"
    if command -v lldpctl >/dev/null 2>&1; then
        lldp_output=$(lldpctl 2>/dev/null)
        if [ -z "$lldp_output" ]; then
            echo -e "${RED}No LLDP information found. Please ensure lldpd is running and LLDP is enabled on your switch.${NC}"
        else
            switch_name=$(echo "$lldp_output" | grep -i "SysName" | head -n1 | awk -F': ' '{print $2}' | xargs)
            mgmt_ip=$(echo "$lldp_output" | grep -i "MgmtIP" | head -n1 | awk -F': ' '{print $2}' | xargs)
            port=$(echo "$lldp_output" | grep -i "PortDescr" | head -n1 | awk -F': ' '{print $2}' | xargs)
            link_speed=$(echo "$lldp_output" | grep -i "MAU oper type" | head -n1 | awk -F': ' '{print $2}' | xargs)
            local_iface=$(echo "$lldp_output" | grep -m1 -E '^Interface:' | awk -F'[:,]' '{print $2}' | xargs)
            if [[ "$(uname -s)" == "Darwin" ]]; then
                vlans=$(echo "$lldp_output" | grep -E '^\s*VLAN:' | while read -r line; do
                    vlan_id=$(echo "$line" | awk -F'[:,]' '{print $2}' | xargs)
                    pvid=$(echo "$line" | grep -o 'pvid: [^ ]*' | awk '{print $2}')
                    vlan_name=$(echo "$line" | sed -E 's/.*pvid: (yes|no) ?//;s/^VLAN: [^,]+, pvid: (yes|no) ?//')
                    if [ "$pvid" = "yes" ]; then
                        echo -e "\033[0;32m$vlan_id${vlan_name:+ $vlan_name}\033[0m"
                    else
                        echo "$vlan_id${vlan_name:+ $vlan_name}"
                    fi
                done | awk '!a[$0]++' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
            else
                vlans=$(echo "$lldp_output" | grep -i "^[[:space:]]*VLAN:" | while read -r line; do
                    vlan_id=$(echo "$line" | awk -F'[:,]' '{print $2}' | xargs)
                    pvid=$(echo "$line" | grep -o 'pvid: [^ ]*' | awk '{print $2}')
                    vlan_name=$(echo "$line" | sed -E 's/.*pvid: (yes|no) ?//;s/^VLAN: [^,]+, pvid: (yes|no) ?//')
                    if [ "$pvid" = "yes" ]; then
                        echo -e "\033[0;32m$vlan_id${vlan_name:+ $vlan_name}\033[0m"
                    else
                        echo "$vlan_id${vlan_name:+ $vlan_name}"
                    fi
                done | awk '!a[$0]++' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
            fi
            has_pvid_vlan=$(echo "$lldp_output" | grep -E '^[[:space:]]*VLAN:' | grep -q 'pvid: yes' && echo 1 || echo 0)
            if { [ -z "$switch_name" ] || [ "$switch_name" = "Unknown" ]; } && \
               { [ -z "$mgmt_ip" ] || [ "$mgmt_ip" = "Unknown" ]; } && \
               { [ -z "$port" ] || [ "$port" = "Unknown" ]; }; then
                if pgrep lldpd >/dev/null 2>&1; then
                    echo -e "${RED}No valid LLDP information received. lldpd is running, but no LLDP data was found. Please ensure LLDP is enabled on your switch and the device is connected.${NC}"
                else
                    echo -e "${YELLOW}lldpd service is not running. Attempting to start it...${NC}"
                    if [[ "$(uname -s)" == "Darwin" ]]; then
                        sudo brew services start lldpd
                    else
                        sudo systemctl start lldpd || sudo service lldpd start
                    fi
                    sleep 2
                    if pgrep lldpd >/dev/null 2>&1; then
                        lldp_output=$(lldpctl 2>/dev/null)
                        switch_name=$(echo "$lldp_output" | grep -i "SysName" | head -n1 | awk -F': ' '{print $2}' | xargs)
                        mgmt_ip=$(echo "$lldp_output" | grep -i "MgmtIP" | head -n1 | awk -F': ' '{print $2}' | xargs)
                        port=$(echo "$lldp_output" | grep -i "PortDescr" | head -n1 | awk -F': ' '{print $2}' | xargs)
                        link_speed=$(echo "$lldp_output" | grep -i "MAU oper type" | head -n1 | awk -F': ' '{print $2}' | xargs)
                        local_iface=$(echo "$lldp_output" | grep -m1 -E '^Interface:' | awk -F'[:,]' '{print $2}' | xargs)
                        if [ -n "$switch_name" ] || [ -n "$mgmt_ip" ] || [ -n "$port" ]; then
                            if [[ "$(uname -s)" == "Darwin" ]]; then
                                vlans=$(echo "$lldp_output" | grep -E '^\s*VLAN:' | while read -r line; do
                                    vlan_id=$(echo "$line" | awk -F'[:,]' '{print $2}' | xargs)
                                    pvid=$(echo "$line" | grep -o 'pvid: [^ ]*' | awk '{print $2}')
                                    vlan_name=$(echo "$line" | sed -E 's/.*pvid: (yes|no) ?//;s/^VLAN: [^,]+, pvid: (yes|no) ?//')
                                    if [ "$pvid" = "yes" ]; then
                                        echo -e "\033[0;32m$vlan_id${vlan_name:+ $vlan_name}\033[0m"
                                    else
                                        echo "$vlan_id${vlan_name:+ $vlan_name}"
                                    fi
                                done | awk '!a[$0]++' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                            else
                                vlans=$(echo "$lldp_output" | grep -i "^[[:space:]]*VLAN:" | while read -r line; do
                                    vlan_id=$(echo "$line" | awk -F'[:,]' '{print $2}' | xargs)
                                    pvid=$(echo "$line" | grep -o 'pvid: [^ ]*' | awk '{print $2}')
                                    vlan_name=$(echo "$line" | sed -E 's/.*pvid: (yes|no) ?//;s/^VLAN: [^,]+, pvid: (yes|no) ?//')
                                    if [ "$pvid" = "yes" ]; then
                                        echo -e "\033[0;32m$vlan_id${vlan_name:+ $vlan_name}\033[0m"
                                    else
                                        echo "$vlan_id${vlan_name:+ $vlan_name}"
                                    fi
                                done | awk '!a[$0]++' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
                            fi
                            echo -e "${BLUE}Local Interface:${NC} ${local_iface:-Unknown}"
                            echo -e "${BLUE}Switch Name:${NC} ${switch_name:-Unknown}"
                            echo -e "${BLUE}Management IP:${NC} ${mgmt_ip:-Unknown}"
                            echo -e "${BLUE}Connected Port:${NC} ${port:-Unknown}"
                            echo -e "${BLUE}Negotiated Link Speed:${NC} ${link_speed:-Unknown}"
                            echo -e "${BLUE}VLAN(s):${NC} ${vlans:-Unknown}"
                            if [ "$has_pvid_vlan" -eq 1 ]; then
                                echo -e "${GREEN}Note:${NC} The VLAN in green is the PVID (untagged) VLAN."
                            fi
                        else
                            echo -e "${RED}Failed to get valid LLDP information after starting lldpd. Please check your network and switch configuration.${NC}"
                        fi
                    else
                        echo -e "${RED}Failed to start lldpd service. Please check your installation.${NC}"
                    fi
                fi
                return
            fi
            echo -e "${BLUE}Local Interface:${NC} ${local_iface:-Unknown}"
            echo -e "${BLUE}Switch Name:${NC} ${switch_name:-Unknown}"
            echo -e "${BLUE}Management IP:${NC} ${mgmt_ip:-Unknown}"
            echo -e "${BLUE}Connected Port:${NC} ${port:-Unknown}"
            echo -e "${BLUE}Negotiated Link Speed:${NC} ${link_speed:-Unknown}"
            echo -e "${BLUE}VLAN(s):${NC} ${vlans:-Unknown}"
            if [ "$has_pvid_vlan" -eq 1 ]; then
                echo -e "${GREEN}Note:${NC} The VLAN in green is the PVID (untagged) VLAN."
            fi
        fi
    else
        echo -e "${RED}Unable to locate the lldpctl command.${NC}"
    fi
    echo ""
    echo -e "${GREEN}Press any key to continue...${NC}"
    read -n 1 -s
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
