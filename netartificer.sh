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

VERSION="1.0" # Script version. Used in banner and the upcoming updater.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # Directory of the script.
TOOLS_DIR="$SCRIPT_DIR/tools" # Directory containing utility scripts.
CONFIG_FILE="$SCRIPT_DIR/settings.conf" # Contains user settings.
# Check for the config file, source it if it exists, create it and source it if not.
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}Config file not found. Creating default config at $CONFIG_FILE...${NC}"
    cat > "$CONFIG_FILE" <<EOF
# config.conf - Configuration file for net_script

# Default SSH username for switch connections
SSH_USER="admin"

# Logging configuration (enabled/disabled)
LOGGING="enabled"
# Log file name (relative to script directory)
LOG_FILENAME="net_script.log"
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

# Main menu loop: Provides the central hub for accessing network tools and configurations.
while true; do
    show_banner
    echo -e "${BLUE}Network Interfaces:${NC}"
    interfaces_output=$(display_interfaces)  # List available network interfaces.
    echo -e "$interfaces_output"
    echo ""
    # Present the main menu options.
    echo -e "${BLUE}Menu Options:${NC}"
    echo -e "${BLUE}1)${NC} Show LLDP Information"
    echo -e "${BLUE}2)${NC} Show ARP Table"
    echo -e "${BLUE}3)${NC} Switch VLAN Configuration Utility"
    echo -e "${BLUE}4)${NC} LAG Configuration Utility"
    echo -e "${BLUE}5)${NC} Cable Tester"
    echo -e "${BLUE}6)${NC} Network Utilities"
    echo -e "${BLUE}7)${NC} Refresh Interfaces"
    echo -e "${BLUE}8)${NC} Settings Configuration"
    echo -e "${BLUE}0)${NC} Exit"
    echo ""
    read -e -rp "Enter your choice [0-8]: " choice
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
            log "Interfaces refreshed.";;
        8)
            configure_settings;;
        0)
            clear; echo -e "${GREEN}Goodbye!${NC}"; log "User exited the script."; exit 0;;
        *)
            echo -e "${RED}Invalid choice. Please select a valid option.${NC}"; sleep 1;;
    esac

done

# At script exit, cleanup sensitive variables
trap 'unset SWITCH_PASSWORD; unset SSH_USER' EXIT