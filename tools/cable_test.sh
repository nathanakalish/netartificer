#!/bin/bash
# Cable diagnostics for Aruba, Cisco, and Netgear switches


# Banner helper using common functions
cable_banner() {
    print_switch_banner "$@"
}

# Main cable test function, loops for repeated tests
cable_test() {
    while true; do
        # Try to auto-detect switch info using LLDP
        IFS='|' read -r detected_name detected_ip detected_port detected_vendor <<< "$(get_lldp_info)"
        cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"

        # If switch info is detected, confirm with the user
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

        # Prompt for switch IP if not detected or confirmed
        if [[ -z "$detected_ip" ]]; then
            cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            while true; do
                read -e -rp "Enter switch management IP: " ip
                [[ "$ip" == "qq" ]] && return
                valid_ip "$ip" && detected_ip="$ip" && break || echo -e "${RED}Invalid IP.${NC}"
            done
        fi

        # Prompt for switch name if not detected
        if [[ -z "$detected_name" ]]; then
            cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            read -e -rp "Enter switch name (optional): " name
            [[ "$name" == "qq" ]] && return
            detected_name="$name"
        fi

        # Prompt for switch vendor if not detected
        if [[ -z "$detected_vendor" ]]; then
            cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
            while true; do
                cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
                read -e -rp "Enter switch vendor (Cisco/Aruba/Netgear): " vendor
                [[ "$vendor" == "qq" ]] && return
                valid_vendor "$vendor" && detected_vendor="$vendor" && break || echo -e "${RED}Invalid vendor.${NC} Only Cisco, Aruba, and Netgear are supported. Use qq to quit."
            done
        fi

        # Prompt for SSH username and test SSH connection
        cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        read -e -rp "SSH Username [default: $SSH_USER]: " input_user
        [[ "$input_user" == "qq" ]] && return
        [[ -z "$input_user" ]] && input_user="$SSH_USER"
        SSH_USER="$input_user"

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

        # Prompt for port to test
        cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        while true; do
            read -e -rp "Enter port to test (e.g., 1/1/13 or 13): " port
            [[ "$port" == "qq" ]] && return
            port=$(echo "$port" | tr -d ' ')
            valid_port "$port" && break || echo -e "${RED}Invalid port.${NC}"
        done
        port_fmt=$(format_port "$port")

        # Warn if testing the port currently connected to
        if [[ "$detected_ip" == "$detected_ip" && -n "$detected_port" ]]; then
            curr_port_fmt=$(format_port "$detected_port")
            if [[ "$curr_port_fmt" == "$port_fmt" ]]; then
                cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
                while true; do
                    echo -e "${YELLOW}Warning: You are testing the port you are connected to ($curr_port_fmt)!${NC}"
                    read -e -rp "Proceed anyway? (y/n/qq): " override
                    case "$override" in
                        y|n|qq) break;;
                        *) echo -e "${RED}Please enter y, n, or qq.${NC}";;
                    esac
                done
                [[ "$override" == "qq" || "$override" == "n" ]] && echo -e "${RED}Aborted.${NC}" && return
            fi
        fi

        # Run the cable test based on the detected vendor
        cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        echo -e "${BLUE}Running cable test.${NC}"
        case "$detected_vendor" in
            Aruba)
                # Run cable test
                cmds1=("diagnostics" "diag cable test $port_fmt" "y" "exit")
                cmds2=("diagnostics" "diag cable show $port_fmt" "exit")
                log_out1=""
                log_out2=""
                if [[ -z "$SWITCH_PASSWORD" ]]; then
                    log_out1=$(ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds1[@]}")
EOF
                    )
                else
                    log_out1=$(sshpass -p "$SWITCH_PASSWORD" ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds1[@]}")
EOF
                    )
                fi
                [[ "${LOGGING:-enabled}" == "enabled" ]] && log "Cable test started on $detected_ip port $port_fmt\nSSH output:\n$log_out1"
                cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
                echo -e "${BLUE}Waiting for test to complete...${NC}"
                sleep 10
                if [[ -z "$SWITCH_PASSWORD" ]]; then
                    log_out2=$(ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds2[@]}")
EOF
                    )
                else
                    log_out2=$(sshpass -p "$SWITCH_PASSWORD" ssh -q -T -o StrictHostKeyChecking=no "$SSH_USER@$detected_ip" <<EOF
$(printf '%s\n' "${cmds2[@]}")
EOF
                    )
                fi
                [[ "${LOGGING:-enabled}" == "enabled" ]] && log "Cable test result on $detected_ip port $port_fmt\nSSH output:\n$log_out2"
                # Only show the output of diag cable show
                result=$(echo "$log_out2" | awk '/diag cable show/{flag=1;next}/exit/{flag=0}flag')
                if [[ -z "$result" ]]; then
                    # fallback: show everything between 'diag cable show' and 'exit'
                    result=$(echo "$log_out2" | sed -n '/diag cable show/,/exit/p' | sed '1d;$d')
                fi
                cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
                # Only show the first 7 lines of the output of 'diag cable show' and format it
                echo -e "${GREEN}Cable test result for $port_fmt:${NC}"
                echo "$result" | head -n 7 | awk '
                BEGIN { IGNORECASE=0; }
                {
                    line = $0;
                    gsub(/good/, "\033[0;32m&\033[0m", line);
                    gsub(/open|short|inter_short|high_impedance|low_impedance|failed/, "\033[0;31m&\033[0m", line);
                    gsub(/---------------------------------------------------------------------/, "\033[0;32m&\033[0m", line);
                    gsub(/\(Ohms\)/, "\033[0;32m&\033[0m", line);
                    gsub(/\(Meters\)/, "\033[0;32m&\033[0m", line);
                    gsub(/Interface|Pinout|Cable|Status|Impedance|Distance|MDI|Mode/, "\033[0;36m&\033[0m", line);
                    gsub(/\*/, "\033[1;33m&\033[0m", line);
                    print line;
                }'
                echo ""
                echo -e "${YELLOW}*Distance is based on the distance from the switch. Reported distance on non-good lines is the distance to the fault.${NC}"
                echo ""
                ;;
            Cisco)
                echo -e "${YELLOW}Cable test for Cisco is not implemented. Placeholder only.${NC}"
                echo -e "Running cable test on Cisco port $port_fmt..."
                sleep 2
                echo -e "${GREEN}Cable test result for $port_fmt:${NC}\n[Placeholder: Cisco cable test output]"
                ;;
            Netgear)
                echo -e "${YELLOW}Cable test for Netgear is not implemented. Placeholder only.${NC}"
                echo -e "Running cable test on Netgear port $port_fmt..."
                sleep 2
                echo -e "${GREEN}Cable test result for $port_fmt:${NC}\n[Placeholder: Netgear cable test output]"
                ;;
        esac
        echo -e "${GREEN}Press any key to continue...${NC}"
        read -n 1 -s
        echo ""
        cable_banner "$detected_name" "$detected_ip" "$detected_port" "$detected_vendor"
        while true; do
            read -e -rp "Run another test? (y/n): " test_again
            case "$test_again" in
                y|Y) break;;
                n|N|qq) return;;
                *) echo -e "${RED}Please enter y or n.${NC}";;
            esac
        done
        [[ "$test_again" =~ ^[yY]$ ]] || return
    done
}

declare -fx cable_test
