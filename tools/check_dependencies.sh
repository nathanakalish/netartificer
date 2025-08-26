#!/bin/bash
# check_dependencies.sh - Checks and installs required dependencies for NetArtificer

# Figure out what OS we're running on (Linux or macOS)
OS_TYPE="$(uname -s)"
# List of dependencies for the different tools in the script
if [[ "$OS_TYPE" == "Darwin" ]]; then
    DEPS=("lldpd" "ssh" "arp" "awk" "sed" "grep" "ping" "dig" "sshpass" "wakeonlan" "speedtest-cli" "nmap" "mtr" "snmpget" "whois")
else
    DEPS=("lldpd" "ssh" "arp" "awk" "sed" "grep" "ping" "dig" "sshpass" "wakeonlan" "speedtest-cli" "nmap" "mtr" "snmpget" "whois" "brctl" "hostapd" "jq")
fi

check_dependencies() {
    show_banner
    missing=()
    # Loop through all the dependencies and see if they're installed
    for dep in "${DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done

    # If anything is missing, let the user know and offer to install
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Some dependencies are missing: ${GREEN}${missing[*]}${NC}"
        invalid_dep_msg=""
        while true; do
            [ -n "$invalid_dep_msg" ] && echo -e "${RED}$invalid_dep_msg${NC}"
            read -e -rp $'\033[0;36mDo you want to install them? (y/n):\033[0m ' ans
            [ "$ans" = "qq" ] && return
            if [[ "$ans" =~ ^[YyNn]$ ]]; then
                break
            else
                clear
                echo -e "${YELLOW}Some dependencies are missing: ${GREEN}${missing[*]}${NC}"
                invalid_dep_msg="Invalid input. Please enter 'y' or 'n', or 'qq' to quit."
            fi
        done
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            if [[ "$OS_TYPE" == "Darwin" ]]; then
                # macOS: Use Homebrew for installs
                if ! command -v brew >/dev/null 2>&1; then
                    echo -e "${RED}Homebrew is not installed. Please install Homebrew first: https://brew.sh/${NC}"
                    exit 1
                fi
                brew_pkgs=()
                # Some tools have different names in Homebrew
                for dep in "${missing[@]}"; do
                    if [ "$dep" = "dig" ]; then
                        brew_pkgs+=("bind")
                    elif [ "$dep" = "snmpget" ]; then
                        brew_pkgs+=("net-snmp")
                    else
                        brew_pkgs+=("$dep")
                    fi
                done
                echo -e "${BLUE}Installing ${brew_pkgs[*]} via brew...${NC}"
                sudo -u "${SUDO_USER:-$USER}" brew install "${brew_pkgs[@]}"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Failed to install some dependencies. Exiting.${NC}"
                    exit 1
                fi
            else
                # Assume Linux: Use apt for installs (Will add other package managers later)
                apt_pkgs=()
                # Some tools have different names in apt
                for dep in "${missing[@]}"; do
                    if [ "$dep" = "dig" ]; then
                        apt_pkgs+=("dnsutils")
                    elif [ "$dep" = "snmpget" ]; then
                        apt_pkgs+=("snmp")
                    elif [ "$dep" = "brctl" ]; then
                        apt_pkgs+=("bridge-utils")
                    else
                        apt_pkgs+=("$dep")
                    fi
                done
                echo -e "${BLUE}Installing ${apt_pkgs[*]} via apt...${NC}"
                apt update && apt install -y "${apt_pkgs[@]}"
                if [ $? -ne 0 ]; then
                    echo -e "${RED}Failed to install some dependencies. Exiting.${NC}"
                    exit 1
                fi
            fi
        else
            echo -e "${RED}Cannot continue without required dependencies. Exiting.${NC}"
            exit 1
        fi
    fi
}
