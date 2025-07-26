#!/bin/bash
# switch_vlan.sh - Quick VLAN config tool for Aruba, Cisco, and Netgear switches

# Assumes: LOGGING, LOG_FILE, SSH_USER, show_banner, log, and color vars are sourced from main script


# Banner helper using common functions
vlan_banner() {
    print_switch_banner "$@"
}

# Main function for the VLAN switcher
switch_vlan() {
    # 1. Try to auto-detect switch info with LLDP
    IFS='|' read -r detected_name detected_ip detected_port detected_vendor <<< "$(get_lldp_info)"
    vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"

    # 2. Ask user if the detected switch is right
    if [[ -n "$detected_name" && -n "$detected_ip" ]]; then
        while true; do
            read -e -rp "Is the detected switch ($detected_name at $detected_ip) correct? (Y/n/qq): " ans
            ans=${ans:-y}
            case "$ans" in
                y|n|qq) break;;
                *) echo -e "${RED}Please enter y, n, or qq.${NC}";;
            esac
        done
        [[ "$ans" == "qq" ]] && return
        [[ "$ans" == "n" ]] && detected_ip="" && detected_name="" && detected_vendor=""
    fi

    # 2b. If we didn't detect, ask for details
    if [[ -z "$detected_ip" ]]; then
        while true; do
            vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            read -e -rp "Enter switch management IP: " ip
            [[ "$ip" == "qq" ]] && return
            ip=$(echo "$ip" | tr -d ' ')
            valid_ip "$ip" && detected_ip="$ip" && break || echo -e "${RED}Invalid IP.${NC}"
        done
    fi
    if [[ -z "$detected_name" ]]; then
        vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        read -e -rp "Enter switch name (optional): " name
        [[ "$name" == "qq" ]] && return
        detected_name="$name"
    fi
    if [[ -z "$detected_vendor" ]]; then
        while true; do
            vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            read -e -rp "Enter switch vendor (Cisco/Aruba/Netgear): " vendor
            [[ "$vendor" == "qq" ]] && return
            vendor=$(echo "$vendor" | tr -d ' ')
            valid_vendor "$vendor" && detected_vendor="$vendor" && break || echo -e "${RED}Invalid vendor.${NC} Only Cisco, Aruba, and Netgear are supported. Use qq to quit."
        done
    fi

    # 4. Ask for SSH username (default to $SSH_USER)
    while true; do
        vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        read -e -rp "SSH Username [default: $SSH_USER]: " input_user
        [[ "$input_user" == "qq" ]] && return
        input_user=$(echo "$input_user" | tr -d ' ')
        [[ -z "$input_user" ]] && input_user="$SSH_USER"
        [[ "$input_user" =~ ^[a-zA-Z0-9._-]+$ ]] && break || echo -e "${RED}Invalid username.${NC}"
    done
    SSH_USER="$input_user"

    # 5. Test SSH connection (try key, then password if needed)
    echo -e "${BLUE}Testing SSH connection to $detected_ip...${NC}"
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "exit" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        if ! command -v sshpass >/dev/null 2>&1; then
            echo -e "${RED}sshpass required for password auth. Install and try again.${NC}"; return
        fi
        for i in {1..3}; do
            echo -e "${YELLOW}Key based authentication failed. Using password authentication.${NC}"
            read -e -rs -p "SSH Password (attempt $i of 3, or qq to quit): " pw; echo
            [[ "$pw" == "qq" ]] && return
            [[ -z "$pw" ]] && echo -e "${RED}Password required.${NC}" && continue
            sshpass -p "$pw" ssh -o BatchMode=no -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "exit" >/dev/null 2>&1 && { SWITCH_PASSWORD="$pw"; break; } || echo -e "${RED}Auth failed.${NC}"
            [[ $i -eq 3 ]] && echo -e "${RED}Failed 3 times. Returning to menu.${NC}" && return
        done
    else
        SWITCH_PASSWORD=""
        echo -e "${GREEN}Key-based authentication successful.${NC}"
    fi

    # 6. Ask for port or port range
    while true; do
        vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        read -e -rp "Enter first port (e.g., 1/1/29 or 29): " port1
        [[ "$port1" == "qq" ]] && return
        port1=$(echo "$port1" | tr -d ' ')
        valid_port "$port1" && break || echo -e "${RED}Invalid port.${NC}"
    done
    port1_fmt=$(format_port "$port1")
    while true; do
        read -e -rp "Enter last port (blank for single port): " port2
        [[ "$port2" == "qq" ]] && return
        port2=$(echo "$port2" | tr -d ' ')
        if [[ -z "$port2" ]]; then
            port2_fmt=""
            break
        fi
        valid_port "$port2" && port2_fmt=$(format_port "$port2") && break || echo -e "${RED}Invalid port.${NC}"
    done
    if [[ -z "$port2_fmt" ]]; then
        port_range="$port1_fmt"
    else
        port_range="$port1_fmt-$port2_fmt"
    fi

    # 7. Warn if you're about to cut off your own connection
    if [[ -n "$detected_port" ]]; then
        curr_port_fmt=$(format_port "$detected_port")
        if [[ -z "$port2_fmt" ]]; then
            # Single port: warn if configuring the connected port
            if [[ "$curr_port_fmt" == "$port1_fmt" ]]; then
                while true; do
                    echo -e "${YELLOW}Warning: You are configuring the port you are connected to ($curr_port_fmt)!${NC}"
                    echo -e "${YELLOW}If you lose access, try connecting to a different port.${NC}"
                    read -e -rp "Proceed anyway? (y/n/qq): " override
                    case "$override" in
                        y|n|qq) break;;
                        *) echo -e "${RED}Please enter y, n, or qq.${NC}";;
                    esac
                done
                [[ "$override" == "qq" || "$override" == "n" ]] && echo -e "${RED}Aborted.${NC}" && return
            fi
        else
            # Port range: warn if connected port is in range
            if port_in_range "$curr_port_fmt" "$port1_fmt" "$port2_fmt"; then
                while true; do
                    echo -e "${YELLOW}Warning: You are configuring a range that includes the port you are connected to ($curr_port_fmt)!${NC}"
                    echo -e "${YELLOW}If you lose access, try connecting to a different port.${NC}"
                    read -e -rp "Proceed anyway? (y/n/qq): " override
                    case "$override" in
                        y|n|qq) break;;
                        *) echo -e "${RED}Please enter y, n, or qq.${NC}";;
                    esac
                done
                [[ "$override" == "qq" || "$override" == "n" ]] && echo -e "${RED}Aborted.${NC}" && return
            fi
        fi
    fi

    # 8. Ask for port mode and VLANs
    vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
    echo -e "${BLUE}Select port mode:${NC}\n1) Trunk\n2) Access"
    while true; do
        read -e -rp "Enter choice [1-2]: " mode
        [[ "$mode" == "qq" ]] && return
        mode=$(echo "$mode" | tr -d ' ')
        [[ "$mode" =~ ^[12]$ ]] && break || echo -e "${RED}Invalid selection.${NC}"
    done
    if [[ "$mode" == "1" ]]; then
        port_mode="trunk"
        while true; do
            read -e -rp "Enter allowed VLAN IDs (comma-separated): " vlan_list
            [[ "$vlan_list" == "qq" ]] && return
            vlan_list=$(echo "$vlan_list" | tr -d ' ')
            [[ "$vlan_list" =~ ^[0-9]+(,[0-9]+)*$ ]] && break || echo -e "${RED}Invalid VLAN list.${NC}"
        done
        while true; do
            read -e -rp "Enter native VLAN ID: " native_vlan
            [[ "$native_vlan" == "qq" ]] && return
            native_vlan=$(echo "$native_vlan" | tr -d ' ')
            [[ "$native_vlan" =~ ^[0-9]+$ ]] && break || echo -e "${RED}Invalid native VLAN.${NC}"
        done
    else
        port_mode="access"
        while true; do
            read -e -rp "Enter VLAN ID for access mode: " vlan_list
            [[ "$vlan_list" == "qq" ]] && return
            vlan_list=$(echo "$vlan_list" | tr -d ' ')
            [[ "$vlan_list" =~ ^[0-9]+$ ]] && break || echo -e "${RED}Invalid VLAN ID.${NC}"
        done
        native_vlan=""
    fi

    # 9. Build up the commands for the switch (depends on vendor)
    cmds=()
    case "$detected_vendor" in
        Cisco)
            cmds+=("configure terminal" "interface $port_range")
            if [[ "$port_mode" == "trunk" ]]; then
                cmds+=("switchport mode trunk" "switchport trunk allowed vlan $vlan_list" "switchport trunk native vlan $native_vlan")
            else
                cmds+=("switchport mode access" "switchport access vlan $vlan_list")
            fi
            cmds+=("exit")
            save_cmd="write memory"
            ;;
        Aruba)
            cmds+=("en" "configure t" "interface $port_range")
            if [[ "$port_mode" == "trunk" ]]; then
                cmds+=("vlan trunk native $native_vlan" "vlan trunk allowed $vlan_list")
            else
                cmds+=("vlan access $vlan_list")
            fi
            cmds+=("exit" "exit" "exit")
            save_cmd="wr me"
            ;;
        Netgear)
            cmds+=("configure" "interface $port_range")
            if [[ "$port_mode" == "trunk" ]]; then
                cmds+=("switchport mode trunk" "switchport trunk allowed vlan $vlan_list" "switchport trunk native vlan $native_vlan")
            else
                cmds+=("switchport mode access" "switchport access vlan $vlan_list")
            fi
            cmds+=("exit")
            save_cmd="write memory"
            ;;
    esac

    # 10. Actually send the commands to the switch (but don't save yet)
    log_out=""
    vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
    echo -e "${BLUE}Sending configuration to $detected_ip...${NC}"
    if [[ "$detected_vendor" == "Aruba" ]]; then
        # For Aruba, send commands as a block (heredoc style)
        if [[ -z "$SWITCH_PASSWORD" ]]; then
            log_out=$(ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds[@]}")
EOF
            )
        else
            log_out=$(sshpass -p "$SWITCH_PASSWORD" ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds[@]}")
EOF
            )
        fi
    else
        if [[ -z "$SWITCH_PASSWORD" ]]; then
            log_out=$(ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$(printf '%s; ' "${cmds[@]}")" 2>&1)
        else
            log_out=$(sshpass -p "$SWITCH_PASSWORD" ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$(printf '%s; ' "${cmds[@]}")" 2>&1)
        fi
    fi
    [[ "${LOGGING:-enabled}" == "enabled" ]] && log "VLAN config sent to $detected_ip: ${cmds[*]}\nSSH output:\n$log_out"

    # 11. Ask user if it worked before saving
    while true; do
        vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        read -e -rp "Did the configuration apply as intended? (Y/n/qq): " ok
        ok=${ok:-y}
        case "$ok" in
            y|n|qq) break;;
            *) echo -e "${RED}Please enter y, n, or qq.${NC}";;
        esac
    done
    [[ "$ok" == "qq" || "$ok" == "n" ]] && echo -e "${RED}Aborted. No changes written.${NC}" && return
    # Check if switch is still up, offer retry if not
    while true; do
        if [[ -z "$SWITCH_PASSWORD" ]]; then
            ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "exit" >/dev/null 2>&1
        else
            sshpass -p "$SWITCH_PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "exit" >/dev/null 2>&1
        fi
        if [[ $? -eq 0 ]]; then
            break
        else
            vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            echo -e "${RED}Could not connect to the switch at $detected_ip after configuration.${NC}"
            read -e -rp "Retry connection? (y/n): " retry
            case "$retry" in
                y|Y) continue;;
                n|N|qq) echo -e "${RED}Aborted. Can't write config.${NC}"; return;;
                *) echo -e "${RED}Please enter y or n.${NC}";;
            esac
        fi
    done
    # 12. Save the config (new SSH session)
    vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
    echo -e "${BLUE}Writing configuration to switch...${NC}"
    if [[ -z "$SWITCH_PASSWORD" ]]; then
        ssh -tt -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$save_cmd" >/dev/null 2>&1
    else
        sshpass -p "$SWITCH_PASSWORD" ssh -tt -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$save_cmd" >/dev/null 2>&1
    fi
    vlan_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
    echo -e "${GREEN}Configuration written successfully.${NC}"
    # 13. All done!
    echo -e "${GREEN}Press any key to return to menu...${NC}"
    read -n 1 -s
}

# Export for main menu
declare -fx switch_vlan
