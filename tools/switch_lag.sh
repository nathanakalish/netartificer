#!/bin/bash
# switch_lag.sh - Quick LAG config tool for Aruba, Cisco, and Netgear switches

# Assumes: LOGGING, LOG_FILE, SSH_USER, show_banner, log, and color vars are sourced from main script

# Helper: Grab LLDP info and pull out the details we care about
get_lldp_info() {
    local lldp_info lldp_name lldp_ip lldp_port lldp_vendor
    lldp_info=$(lldpctl 2>/dev/null)
    lldp_name=$(echo "$lldp_info" | grep -i "SysName" | head -n1 | awk -F': ' '{print $2}' | xargs)
    lldp_ip=$(echo "$lldp_info" | grep -i "MgmtIP" | head -n1 | awk -F': ' '{print $2}' | xargs)
    lldp_vendor=$(echo "$lldp_info" | grep -i "SysDescr" | awk -F': ' '{print $2}' | grep -i -E "Cisco|Aruba|Netgear" | head -n1 | awk '{print $1}')
    echo "$lldp_name|$lldp_ip|$lldp_vendor"
}

lag_banner() {
    show_banner
    [[ -n "$1" ]] && detected_name="$1"
    [[ -n "$2" ]] && detected_ip="$2"
    [[ -n "$3" ]] && detected_vendor="$3"
    [ -n "$detected_name" ] && echo -e "${BLUE}Switch Name:${NC} $detected_name"
    [ -n "$detected_ip" ] && echo -e "${BLUE}Management IP:${NC} $detected_ip"
    [ -n "$detected_vendor" ] && echo -e "${BLUE}Vendor:${NC} $detected_vendor"
    echo
}

valid_ip() {
    [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

valid_vendor() {
    [[ $1 =~ ^(Cisco|Aruba|Netgear)$ ]]
}

valid_port() {
    [[ $1 =~ ^([0-9]+(/[0-9]+){0,2})$ ]]
}

format_port() {
    [[ $1 =~ "/" ]] && echo "$1" || echo "1/1/$1"
}

switch_lag() {
    # 1. Try to auto-detect switch info with LLDP
    IFS='|' read -r detected_name detected_ip detected_vendor <<< "$(get_lldp_info)"
    lag_banner "$detected_name" "$detected_ip" "$detected_vendor"

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
            lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
            read -e -rp "Enter switch management IP: " ip
            [[ "$ip" == "qq" ]] && return
            ip=$(echo "$ip" | tr -d ' ')
            valid_ip "$ip" && detected_ip="$ip" && break || echo -e "${RED}Invalid IP.${NC}"
        done
    fi
    if [[ -z "$detected_name" ]]; then
        lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
        read -e -rp "Enter switch name (optional): " name
        [[ "$name" == "qq" ]] && return
        detected_name="$name"
    fi
    if [[ -z "$detected_vendor" ]]; then
        while true; do
            lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
            read -e -rp "Enter switch vendor (Cisco/Aruba/Netgear): " vendor
            [[ "$vendor" == "qq" ]] && return
            vendor=$(echo "$vendor" | tr -d ' ')
            valid_vendor "$vendor" && detected_vendor="$vendor" && break || echo -e "${RED}Invalid vendor.${NC} Only Cisco, Aruba, and Netgear are supported. Use qq to quit."
        done
    fi

    # 3. Ask for SSH username (default to $SSH_USER)
    while true; do
        lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
        read -e -rp "SSH Username [default: $SSH_USER]: " input_user
        [[ "$input_user" == "qq" ]] && return
        input_user=$(echo "$input_user" | tr -d ' ')
        [[ -z "$input_user" ]] && input_user="$SSH_USER"
        [[ "$input_user" =~ ^[a-zA-Z0-9._-]+$ ]] && break || echo -e "${RED}Invalid username.${NC}"
    done
    SSH_USER="$input_user"

    # 4. Test SSH connection (try key, then password if needed)
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

    # 5. Ask for LAG (Port-Channel) number
    while true; do
        lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
        read -e -rp "Enter LAG (Port-Channel) number (e.g., 1): " lag_num
        [[ "$lag_num" == "qq" ]] && return
        lag_num=$(echo "$lag_num" | tr -d ' ')
        [[ "$lag_num" =~ ^[0-9]+$ ]] && break || echo -e "${RED}Invalid LAG number.${NC}"
    done

    # 6. Ask for member ports (comma-separated)
    while true; do
        read -e -rp "Enter member ports (comma-separated, e.g., 1/1/1,1/1/2 or 1,2): " lag_ports
        [[ "$lag_ports" == "qq" ]] && return
        lag_ports=$(echo "$lag_ports" | tr -d ' ')
        # Accept single numbers or full notation, format all to full notation
        IFS=',' read -ra ports_arr <<< "$lag_ports"
        formatted_ports=()
        for p in "${ports_arr[@]}"; do
            formatted_ports+=("$(format_port "$p")")
        done
        lag_ports_fmt=$(IFS=','; echo "${formatted_ports[*]}")
        # Validate all formatted ports
        valid=true
        for p in "${formatted_ports[@]}"; do
            valid_port "$p" || valid=false
        done
        $valid && break || echo -e "${RED}Invalid port list.${NC}"
    done

    # 7. Ask for LAG mode (static or LACP)
    echo -e "${BLUE}Select LAG mode:${NC}\n1) Static\n2) LACP"
    while true; do
        read -e -rp "Enter choice [1-2]: " lag_mode
        [[ "$lag_mode" == "qq" ]] && return
        lag_mode=$(echo "$lag_mode" | tr -d ' ')
        [[ "$lag_mode" =~ ^[12]$ ]] && break || echo -e "${RED}Invalid selection.${NC}"
    done
    if [[ "$lag_mode" == "1" ]]; then
        lag_mode_str="static"
    else
        lag_mode_str="lacp"
    fi

    # 8. Build up the commands for the switch (depends on vendor)
    cmds=()
    case "$detected_vendor" in
        Cisco)
            cmds+=("configure terminal" "interface Port-channel$lag_num" "no shutdown")
            [[ "$lag_mode_str" == "lacp" ]] && cmds+=("channel-group $lag_num mode active")
            IFS=',' read -ra ports_arr <<< "$lag_ports_fmt"
            for p in "${ports_arr[@]}"; do
                cmds+=("interface $p" "channel-group $lag_num mode ${lag_mode_str}")
            done
            cmds+=("exit")
            save_cmd="write memory"
            ;;
        Aruba)
            cmds+=("en" "configure t" "interface lag $lag_num")
            [[ "$lag_mode_str" == "lacp" ]] && cmds+=("lacp")
            cmds+=("no shutdown" "exit")
            IFS=',' read -ra ports_arr <<< "$lag_ports_fmt"
            for p in "${ports_arr[@]}"; do
                cmds+=("interface $p" "lag $lag_num")
                [[ "$lag_mode_str" == "lacp" ]] && cmds+=("lacp active")
                cmds+=("exit")
            done
            cmds+=("exit" "exit")
            save_cmd="wr me"
            ;;
        Netgear)
            cmds+=("configure" "interface lag $lag_num")
            [[ "$lag_mode_str" == "lacp" ]] && cmds+=("mode lacp")
            cmds+=("exit")
            IFS=',' read -ra ports_arr <<< "$lag_ports_fmt"
            for p in "${ports_arr[@]}"; do
                cmds+=("interface $p" "channel-group $lag_num mode ${lag_mode_str}")
            done
            cmds+=("exit")
            save_cmd="write memory"
            ;;
    esac

    # 9. Actually send the commands to the switch (but don't save yet)
    log_out=""
    lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
    echo -e "${BLUE}Sending LAG configuration to $detected_ip...${NC}"
    if [[ "$detected_vendor" == "Aruba" ]]; then
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
    [[ "${LOGGING:-enabled}" == "enabled" ]] && log "LAG config sent to $detected_ip: ${cmds[*]}\nSSH output:\n$log_out"

    # 10. Ask user if it worked before saving
    while true; do
        lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
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
            lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
            echo -e "${RED}Could not connect to the switch at $detected_ip after configuration.${NC}"
            read -e -rp "Retry connection? (y/n): " retry
            case "$retry" in
                y|Y) continue;;
                n|N|qq) echo -e "${RED}Aborted. Can't write config.${NC}"; return;;
                *) echo -e "${RED}Please enter y or n.${NC}";;
            esac
        fi
    done
    # 11. Save the config (new SSH session)
    lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
    echo -e "${BLUE}Writing configuration to switch...${NC}"
    if [[ -z "$SWITCH_PASSWORD" ]]; then
        ssh -tt -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$save_cmd" >/dev/null 2>&1
    else
        sshpass -p "$SWITCH_PASSWORD" ssh -tt -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" "$save_cmd" >/dev/null 2>&1
    fi
    lag_banner "$detected_name" "$detected_ip" "$detected_vendor"
    echo -e "${GREEN}Configuration written successfully.${NC}"
    echo -e "${GREEN}Press any key to return to menu...${NC}"
    read -n 1 -s
}

declare -fx switch_lag
