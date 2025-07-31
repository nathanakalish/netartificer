#!/bin/bash
# main.sh - Main script for NetArtificer

# Color variables
# some things don't get colored properly when just changing these variables, so you'll need to do a find and replace
#BLUE='\033[0;34m'    # Dark Blue - Main Color
BLUE='\033[0;36m'    # Cyan - Main color
GREEN='\033[0;32m'   # Green for user input and good things.
YELLOW='\033[1;33m'  # Yellow for warnings or user input requests.
RED='\033[0;31m'     # Red for bad things.
NC='\033[0m'         # Default color for the terminal.

VERSION="2.4" # Script version. Used in banner and the upcoming updater.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # Directory of the script.
TOOLS_DIR="$SCRIPT_DIR/tools" # Directory containing utility scripts.
CONFIG_FILE="$SCRIPT_DIR/settings.conf" # Contains user settings.
# Check for the config file, source it if it exists, create it and source it if not.
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    HOSTNAME=$(hostname)
    RANDPASS=$(shuf -i 10000000-99999999 -n 1)
    echo -e "${YELLOW}Config file not found. Creating default config at $CONFIG_FILE...${NC}"
    cat > "$CONFIG_FILE" <<EOF
# config.conf - Configuration file for NetArtificer

# Default SSH username for switch connections
SSH_USER="admin"

# Logging configuration (enabled/disabled)
LOGGING="enabled"
# Log file name (relative to script directory)
LOG_FILENAME="netartificer.log"
# Access Point SSID and passphrase
AP_SSID="$HOSTNAME"
AP_PASSPHRASE="$RANDPASS"
# Hide Tailscale LLDP information (enabled/disabled)
HIDE_TAILSCALE_LLDP="disabled"
# GitHub user and repo for updates
GITHUB_USER="nathanakalish"
GITHUB_REPO="netartificer"
# GitHub branch for updates
GITHUB_BRANCH="main"
EOF
    source "$CONFIG_FILE"
fi
LOG_FILE="$SCRIPT_DIR/$LOG_FILENAME" # Log file for script activity. It's half-assed now, but I'm working on better logging.

# Prints usage information for NetArtificer.
print_help() {
    echo -e "${BLUE}NetArtificer - Network Utility Toolkit${NC}"
    echo -e "${GREEN}Usage:${NC} $0 [--OPTION]"
    echo ""
    echo -e "${BLUE}Options:${NC}"
    echo -e "  ${BLUE}--help${NC}              Show this help message and exit."
    echo -e "  ${BLUE}--ping${NC}              Execute ping utility."
    echo -e "  ${BLUE}--tdr${NC}|${BLUE}--cable-test${NC}  Execute cable test utility."
    echo -e "  ${BLUE}--lldp${NC}              Display LLDP information."
    echo -e "  ${BLUE}--arp${NC}               Display ARP table."
    echo -e "  ${BLUE}--vlan${NC}              Configure VLAN."
    echo -e "  ${BLUE}--settings${NC}          Configure settings."
    echo -e "  ${BLUE}--dns${NC}               Execute DNS lookup utility."
    echo -e "  ${BLUE}--scan${NC}              Execute port scanning utility."
    echo -e "  ${BLUE}--wol${NC}               Execute Wake on LAN utility."
    echo -e "  ${BLUE}--speed${NC}             Execute speed test utility."
    echo -e "  ${BLUE}--whois${NC}             Execute WHOIS lookup utility."
    echo -e "  ${BLUE}--sweep${NC}             Execute ping sweep utility."
    echo -e "  ${BLUE}--snmp${NC}              Execute SNMP monitoring."
    echo ""
    echo -e "${BLUE}In the script, you can use qq in any non-menu input to${NC}"
    echo -e "${BLUE}stop running the current tool and return to the menu.${NC}"
    echo ""
    echo -e "${BLUE}Run without arguments to launch the interactive menu.${NC}"
}

# Rerun the script as root if it isn't already.
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Script is not running as root. Re-running with sudo...${NC}"
    exec sudo "$0" "$@"
fi

# Adds a line to the log file with the current timestamp if logging is turned on.
log() {
    if [ "${LOGGING:-enabled}" = "enabled" ]; then
        local message="$1"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}

# Make sure all the scripts in the tools directory are executable if they aren't already.
for tool_file in "$TOOLS_DIR"/*; do
    if [ -f "$tool_file" ] && head -n 1 "$tool_file" | grep -q '^#!/bin/bash'; then
        [ ! -x "$tool_file" ] && chmod +x "$tool_file"
    fi
done

# Source all bash scripts in TOOLS_DIR that start with #!/bin/bash. Good for new functions. Just add a menu option.
# Maybe automatic menu entries later. Can lead the way to "Extensions".
for tool_file in "$TOOLS_DIR"/*; do
    if [ -f "$tool_file" ] && head -n 1 "$tool_file" | grep -q '^#!/bin/bash'; then
        source "$tool_file"
    fi
done

# Clears the terminal and displays a centered banner with the name of the tool and version.
show_banner() {
    clear
    local term_width
    term_width=$(tput cols)
    # :)
    local smile=""
    if (( RANDOM % 100 == 0 )); then
        smile=" :)"
    fi
    local title="NetArtificer v$VERSION"
    local title_length=${#title}
    local smile_length=${#smile}
    local padding=$(( (term_width - title_length - smile_length) / 2 ))
    printf "%${term_width}s\n" | tr " " "="
    printf "%${padding}s" ""
    echo -en "${BLUE}${title}"
    if [ -n "$smile" ]; then
        echo -en "${GREEN}${smile}${NC}"
    fi
    echo -e "${NC}"
    printf "%${term_width}s\n" | tr " " "="
}

# Parse command-line flags for direct function execution. They require input still once run, but skip the menus.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ping)
            ping_host; clear; exit 0;;
        --tdr|--cable-test)
            cable_test; clear; exit 0;;
        --lldp)
            display_lldp_info; clear; exit 0;;
        --arp)
            display_arp_table; clear; exit 0;;
        --vlan)
            switch_vlan; clear; exit 0;;
        --settings)
            configure_settings; clear; exit 0;;
        --dns)
            dns_lookup; clear; exit 0;;
        --scan)
            port_scan; clear; exit 0;;
        --wol)
            wake_on_lan; clear; exit 0;;
        --speed)
            speed_test; clear; exit 0;;
        --whois)
            whois_lookup; clear; exit 0;;
        --sweep)
            ping_sweep; clear; exit 0;;
        --snmp)
            snmp_monitor; clear; exit 0;;
        --help)
            print_help; exit 0;;
        *)
            # Unknown flag, ignore and continue
            ;;
    esac
    shift
done

# Check for required dependencies (Run in check_dependencies). May make this a menu option later.
check_dependencies

# Ensure lldpd is enabled and running
if command -v lldpd >/dev/null 2>&1; then
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable lldpd >/dev/null 2>&1
        sudo systemctl start lldpd >/dev/null 2>&1
    elif command -v service >/dev/null 2>&1; then
        sudo service lldpd start >/dev/null 2>&1
    fi
    # Fallback: try to start if not running
    if ! pgrep lldpd >/dev/null 2>&1; then
        sudo lldpd >/dev/null 2>&1 &
    fi
fi

# Function: network_utilities_menu
# Displays a submenu for network tools and executes the selected utility.
network_utilities_menu() {
    while true; do
        show_banner
        echo -e "${BLUE}Network Interfaces:${NC}"
        interfaces_output=$(display_interfaces)
        echo -e "$interfaces_output"
        echo ""
        echo -e "${BLUE}Network Utilities Options:${NC}"
        echo -e "${BLUE}1)${NC} Ping"
        echo -e "${BLUE}2)${NC} Traceroute"
        echo -e "${BLUE}3)${NC} DNS Lookup"
        echo -e "${BLUE}4)${NC} Port Scan"
        echo -e "${BLUE}5)${NC} Wake on LAN"
        echo -e "${BLUE}6)${NC} Speed Test"
        echo -e "${BLUE}7)${NC} WHOIS Lookup"
        echo -e "${BLUE}8)${NC} Ping Sweep"
        echo -e "${BLUE}9)${NC} SNMP Monitoring"
        echo -e "${BLUE}0)${NC} Go Back"
        echo ""
        read -e -p $'Enter your choice [0-9]: ' util_choice
        case $util_choice in
            1)
                ping_host; log "Executed ping utility.";;
            2)
                mtr_trace; log "Executed MTR traceroute.";;
            3)
                dns_lookup; log "Executed DNS lookup utility.";;
            4)
                port_scan; log "Executed port scanning utility.";;
            5)
                wake_on_lan; log "Executed Wake on LAN utility.";;
            6)
                speed_test; log "Executed speed test utility.";;
            7)
                whois_lookup; log "Executed WHOIS lookup utility.";;
            8)
                ping_sweep; log "Executed ping sweep utility.";;
            9)
                snmp_monitor; log "Executed SNMP monitoring.";;
            0)
                break;;
            *)
                echo -e "${RED}Invalid choice. Please select a valid option.${NC}"; sleep 1;;
        esac
    done
}

AP_STATUS_FILE="/tmp/netartificer_ap_status"
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

# Helper: Force update NetArtificer from GitHub
force_update_netartificer() {
    echo -e "${BLUE}Forcing update...${NC}"
    cd "$SCRIPT_DIR"
    tmpdir=$(mktemp -d)
    github_user="${GITHUB_USER:-nathanakalish}"
    github_repo="${GITHUB_REPO:-netartificer}"
    github_branch="${GITHUB_BRANCH:-main}"
    git clone --depth 1 --branch "$github_branch" https://github.com/$github_user/$github_repo "$tmpdir" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to clone the repository.${NC}"
        rm -rf "$tmpdir"
        echo -e "${GREEN}Press any key to return to the menu...${NC}"
        read -n 1 -s
        return 1
    fi
    cp -r "$tmpdir"/* "$SCRIPT_DIR"/
    rm -rf "$tmpdir"
    chmod +x "$SCRIPT_DIR/netartificer.sh"
    echo -e "${GREEN}NetArtificer force-updated! Restarting...${NC}"
    sleep 3
    exec "$SCRIPT_DIR/netartificer.sh"
}

# Update NetArtificer from GitHub
update_netartificer() {
    show_banner
    echo -e "${BLUE}Checking for updates...${NC}"
    # Check for internet connectivity
    if ! curl -s --head https://github.com >/dev/null; then
        echo -e "${RED}No internet connection or unable to reach GitHub.${NC}"
        echo -e "${GREEN}Press any key to return to the menu...${NC}"
        read -n 1 -s
        return
    fi
    # Use config vars for GitHub user/repo/branch
    github_user="${GITHUB_USER:-nathanakalish}"
    github_repo="${GITHUB_REPO:-netartificer}"
    github_branch="${GITHUB_BRANCH:-main}"
    github_raw_url="https://raw.githubusercontent.com/$github_user/$github_repo/$github_branch/netartificer.sh"
    github_version=$(curl -s "$github_raw_url" | grep '^VERSION=' | head -n1 | cut -d'"' -f2)
    if [ -z "$github_version" ]; then
        echo -e "${RED}Could not fetch version info from GitHub.${NC}"
        echo -e "${GREEN}Press any key to return to the menu...${NC}"
        read -n 1 -s
        return
    fi
    if [[ "$github_version" > "$VERSION" ]]; then
        echo -e "${YELLOW}Update found! $VERSION => $github_version${NC}"
        read -e -rp "Do you want to update? (Y/n): " update_confirm
        update_confirm=${update_confirm:-y}
        if [[ ! "$update_confirm" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Update cancelled. Press any key to return to the menu...${NC}"
            read -n 1 -s
            return
        fi
        echo -e "${BLUE}Updating NetArtificer...${NC}"
        cd "$SCRIPT_DIR"
        tmpdir=$(mktemp -d)
        git clone --depth 1 --branch "$github_branch" https://github.com/$github_user/$github_repo "$tmpdir" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to clone the repository.${NC}"
            rm -rf "$tmpdir"
            echo -e "${GREEN}Press any key to return to the menu...${NC}"
            read -n 1 -s
            return
        fi
        cp -r "$tmpdir"/* "$SCRIPT_DIR"/
        rm -rf "$tmpdir"
        chmod +x "$SCRIPT_DIR/netartificer.sh"
        echo -e "${GREEN}NetArtificer updated to version $github_version! Restarting...${NC}"
        sleep 3
        exec "$SCRIPT_DIR/netartificer.sh"
    elif [[ "$github_version" < "$VERSION" ]]; then
        echo -e "${YELLOW}You are running a version NEWER than the source! Are you from the future?${NC}"
        echo -e "${BLUE}Would you like to force an update anyway? (y/n):${NC}"
        read -n 1 -r force_update
        echo
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            force_update_netartificer
            return
        else
            echo -e "${GREEN}Press any key to return to the menu...${NC}"
            read -n 1 -s
            return
        fi
    elif [[ "$github_version" == "$VERSION" ]]; then
        echo -e "${GREEN}You are already running the latest version ($VERSION).${NC}"
        echo -e "${BLUE}Would you like to force an update anyway? (y/n):${NC}"
        read -n 1 -r force_update
        echo
        if [[ "$force_update" =~ ^[Yy]$ ]]; then
            force_update_netartificer
            return
        else
            echo -e "${GREEN}Press any key to return to the menu...${NC}"
            read -n 1 -s
            return
        fi
    else
        echo -e "${RED}There was an error with the updater. Please check your setup or try again later.${NC}"
        echo -e "${GREEN}Press any key to return to the menu...${NC}"
        read -n 1 -s
        return
    fi
}

# Main menu loop: Provides the central hub for accessing network tools and configurations.
while true; do
    show_banner
    echo -e "${BLUE}Network Interfaces:${NC}"
    display_interfaces
    echo ""
    # Present the main menu options.
    ap_status=$(get_ap_status)
    if [ "$ap_status" = "running" ]; then
        ap_menu_label="Disable Access Point ${BLUE}|${NC} SSID: '${BLUE}$AP_SSID${NC}' Pass: '${BLUE}$AP_PASSPHRASE${NC}'"
    else
        ap_menu_label="Enable Access Point"
    fi
    echo -e "${BLUE}Menu Options:${NC}"
    echo -e "${BLUE}1)${NC} Show LLDP Information"
    echo -e "${BLUE}2)${NC} Show ARP Table"
    echo -e "${BLUE}3)${NC} Switch VLAN Configuration Utility"
    echo -e "${BLUE}4)${NC} LAG Configuration Utility"
    echo -e "${BLUE}5)${NC} Cable Tester"
    echo -e "${BLUE}6)${NC} Network Utilities"
    echo -e "${BLUE}7)${NC} $ap_menu_label"
    echo -e "${BLUE}8)${NC} Settings Configuration"
    echo -e "${BLUE}9)${NC} Update NetArtificer"
    echo -e "${BLUE}0)${NC} Exit"
    echo ""
    read -e -rp "Enter your choice [0-9]: " choice
    case $choice in
        1)
            display_lldp_info; log "Displayed LLDP information.";;
        2)
            display_arp_table; log "Displayed ARP table.";;
        3)
            switch_vlan;;
        4)
            switch_lag;;
        5)
            cable_test; log "Executed Cable Tester utility.";;
        6)
            network_utilities_menu;;
        7)
            if [ "$ap_status" = "running" ]; then
                disable_ap
                show_banner
                echo -e "${GREEN}Access Point disabled."
                echo -e "${GREEN}Press any key to continue...${NC}"
                read -n 1 -s
            else
                enable_ap
                show_banner
                echo -e "${GREEN}Access Point enabled. SSID: '${NC}$AP_SSID${GREEN}' Pass: '${NC}$AP_PASSPHRASE${GREEN}'${NC}"
                echo -e "${GREEN}Press any key to continue...${NC}"
                read -n 1 -s
            fi
            ;;
        8)
            configure_settings;;
        9)
            update_netartificer;;
        0)
            clear; echo -e "${GREEN}Goodbye!${NC}"; log "User exited the script."; exit 0;;
        *)
            echo -e "${RED}Invalid choice. Please select a valid option.${NC}"; sleep 1;;
    esac

done

# At script exit, cleanup sensitive variables
trap 'unset SWITCH_PASSWORD; unset SSH_USER' EXIT