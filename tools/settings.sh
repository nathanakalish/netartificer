#!/bin/bash
# settings.sh - Change script settings

# Displays the current settings menu.
print_settings_menu() {
    show_banner
    echo -e "${BLUE}Current Settings:${NC}"
    echo -e "${BLUE}----------------------${NC}"
    echo -e "${BLUE}1)${NC} Default SSH Username: ${GREEN}$SSH_USER${NC}"
    echo -e "${BLUE}2)${NC} Logging: ${GREEN}$LOGGING${NC}"
    echo -e "${BLUE}3)${NC} Log File: ${GREEN}$LOG_FILENAME${NC}"
    echo -e "${BLUE}4)${NC} AP SSID: ${GREEN}$AP_SSID${NC}"
    echo -e "${BLUE}5)${NC} AP Passphrase: ${GREEN}$AP_PASSPHRASE${NC}"
    echo -e "${BLUE}6)${NC} Hide Tailscale LLDP Neighbors: ${GREEN}$HIDE_TAILSCALE_LLDP${NC}"
    echo -e "${BLUE}7)${NC} GitHub Username for Updates: ${GREEN}$GITHUB_USER${NC}"
    echo -e "${BLUE}8)${NC} GitHub Repo for Updates: ${GREEN}$GITHUB_REPO${NC}"
    echo -e "${BLUE}9)${NC} GitHub Branch for Updates: ${GREEN}$GITHUB_BRANCH${NC}"
    echo -e "${BLUE}0)${NC} Go Back"
    echo ""
}

# Menu for editing NetArtificer configuration settings.
configure_settings() {
    show_banner
    echo -e "${BLUE}Settings Configuration:${NC}"
    while true; do
        print_settings_menu
        echo -ne "${BLUE}Enter your choice [${NC}0${BLUE}-${NC}9${BLUE}]: ${NC}"
        read -e setting_choice
        case $setting_choice in
            1)
                show_banner
                while true; do
                    [ -n "$invalid_user_msg" ] && echo -e "${RED}$invalid_user_msg${NC}"
                    read -e -rp "Enter new default SSH Username: " new_user
                    [ "$new_user" = "qq" ] && break
                    if [[ -n "$new_user" && "$new_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        update_config_var "SSH_USER" "$new_user"
                        echo -e "${GREEN}Default SSH Username updated to $new_user.${NC}"
                        if [ "${LOGGING:-enabled}" = "enabled" ]; then
                            log "Default SSH Username changed to $new_user."
                        fi
                        sleep 2
                        invalid_user_msg=""
                        break
                    else
                        clear
                        print_settings_menu
                        invalid_user_msg="Invalid username. Please use only letters, numbers, dots, underscores, or hyphens."
                    fi
                done
                source "$CONFIG_FILE" # Reload the config file to update the SSH_USER variable.
                ;;
            2)
                show_banner
                while true; do
                    [ -n "$invalid_logging_msg" ] && echo -e "${RED}$invalid_logging_msg${NC}"
                    read -e -rp "Enable logging? (y/n): " yn_logging
                    [ "$yn_logging" = "qq" ] && break
                    case $yn_logging in
                        y|Y)
                            new_logging="enabled"
                            ;;
                        n|N)
                            new_logging="disabled"
                            ;;
                        *)
                            clear
                            print_settings_menu
                            invalid_logging_msg="No changes made. Please enter 'y' or 'n'."
                            continue
                            ;;
                    esac
                    update_config_var "LOGGING" "$new_logging"
                    LOGGING="$new_logging"
                    echo -e "${GREEN}Logging set to $new_logging.${NC}"
                    if [ "${LOGGING:-enabled}" = "enabled" ]; then
                        log "Logging set to $new_logging."
                    fi
                    sleep 2
                    invalid_logging_msg=""
                    break
                done
                source "$CONFIG_FILE" # Reload the config file to update the LOGGING variable.
                ;;
            3)
                show_banner
                while true; do
                    [ -n "$invalid_log_msg" ] && echo -e "${RED}$invalid_log_msg${NC}"
                    read -e -rp "Enter new log file name (relative to script directory): " new_log
                    [ "$new_log" = "qq" ] && break
                    if [[ -n "$new_log" && "$new_log" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
                        update_config_var "LOG_FILENAME" "$new_log"
                        LOG_FILENAME="$SCRIPT_DIR/$new_log"
                        echo -e "${GREEN}Log file updated to $new_log.${NC}"
                        if [ "${LOGGING:-enabled}" = "enabled" ]; then
                            log "Log file changed to $new_log."
                        fi
                        sleep 2
                        invalid_log_msg=""
                        break
                    else
                        clear
                        print_settings_menu
                        invalid_log_msg="Invalid log file name. Please use only valid filename characters."
                    fi
                done
                source "$CONFIG_FILE" # Reload the config file to update the LOG_FILENAME variable.
                ;;
            4)
                show_banner
                while true; do
                    read -e -rp "Enter new AP SSID: " new_ssid
                    [ "$new_ssid" = "qq" ] && break
                    if [[ -n "$new_ssid" ]]; then
                        update_config_var "AP_SSID" "$new_ssid"
                        echo -e "${GREEN}AP SSID updated to $new_ssid.${NC}"
                        sleep 2
                        break
                    else
                        echo -e "${RED}SSID cannot be empty.${NC}"
                    fi
                done
                source "$CONFIG_FILE"
                ;;
            5)
                show_banner
                while true; do
                    read -e -rp "Enter new AP Passphrase: " new_pass
                    [ "$new_pass" = "qq" ] && break
                    if [[ -n "$new_pass" ]]; then
                        update_config_var "AP_PASSPHRASE" "$new_pass"
                        echo -e "${GREEN}AP Passphrase updated.${NC}"
                        sleep 2
                        break
                    else
                        echo -e "${RED}Passphrase cannot be empty.${NC}"
                    fi
                done
                source "$CONFIG_FILE"
                ;;
            6)
                show_banner
                while true; do
                    read -e -rp "Hide Tailscale LLDP Neighbors? (y/n): " yn_hide
                    [ "$yn_hide" = "qq" ] && break
                    case $yn_hide in
                        y|Y)
                            ts_hide="enabled" ;;
                        n|N)
                            ts_hide="disabled" ;;
                        *)
                            clear
                            print_settings_menu
                            echo -e "${RED}Please enter 'y' or 'n'.${NC}"
                            continue ;;
                    esac
                    update_config_var "HIDE_TAILSCALE_LLDP" "$ts_hide"
                    HIDE_TAILSCALE_LLDP="$ts_hide"
                    echo -e "${GREEN}Hide Tailscale LLDP Neighbors set to $ts_hide.${NC}"
                    sleep 2
                    break
                done
                source "$CONFIG_FILE"
                ;;
            7)
                show_banner
                while true; do
                    read -e -rp "Enter new GitHub username for updates: " new_gh_user
                    [ "$new_gh_user" = "qq" ] && break
                    if [[ -n "$new_gh_user" && "$new_gh_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        update_config_var "GITHUB_USER" "$new_gh_user"
                        GITHUB_USER="$new_gh_user"
                        echo -e "${GREEN}GitHub username updated to $new_gh_user.${NC}"
                        sleep 2
                        break
                    else
                        echo -e "${RED}Invalid GitHub username. Please use only valid characters.${NC}"
                    fi
                done
                source "$CONFIG_FILE"
                ;;
            8)
                show_banner
                while true; do
                    read -e -rp "Enter new GitHub repo for updates: " new_gh_repo
                    [ "$new_gh_repo" = "qq" ] && break
                    if [[ -n "$new_gh_repo" && "$new_gh_repo" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        update_config_var "GITHUB_REPO" "$new_gh_repo"
                        GITHUB_REPO="$new_gh_repo"
                        echo -e "${GREEN}GitHub repo updated to $new_gh_repo.${NC}"
                        sleep 2
                        break
                    else
                        echo -e "${RED}Invalid GitHub repo name. Please use only valid characters.${NC}"
                    fi
                done
                source "$CONFIG_FILE"
                ;;
            9)
                show_banner
                while true; do
                    read -e -rp "Enter GitHub branch for updates (default: main): " new_branch
                    [ "$new_branch" = "qq" ] && break
                    [ -z "$new_branch" ] && new_branch="main"
                    if [[ "$new_branch" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
                        update_config_var "GITHUB_BRANCH" "$new_branch"
                        GITHUB_BRANCH="$new_branch"
                        echo -e "${GREEN}GitHub branch updated to $new_branch.${NC}"
                        sleep 2
                        break
                    else
                        echo -e "${RED}Invalid branch name. Please use only valid characters.${NC}"
                    fi
                done
                source "$CONFIG_FILE"
                ;;
            0)
                # Exit the settings menu to go back to the main menu.
                break
                ;;
            *)
                echo -e "${RED}Invalid selection.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Set sed in-place flag for macOS or Linux
get_sed_inplace_flag() {
    if sed --version 2>/dev/null | grep -q GNU; then
        echo "-i"
    else
        echo "-i ''"
    fi
}

# Update or append a config variable in the config file
update_config_var() {
    local var="$1"
    local value="$2"
    local sed_flag
    sed_flag=$(get_sed_inplace_flag)
    if [ -z "$CONFIG_FILE" ]; then
        echo "CONFIG_FILE is not set. Cannot update config." >&2
        return 1
    fi
    if [ ! -w "$CONFIG_FILE" ]; then
        echo "No write permission for $CONFIG_FILE. Cannot update config." >&2
        return 1
    fi
    # Remove any empty lines for this var
    sed $sed_flag "/^${var}=$/d" "$CONFIG_FILE"
    if grep -q "^${var}=" "$CONFIG_FILE"; then
        sed $sed_flag "s|^${var}=.*|${var}=\"$value\"|" "$CONFIG_FILE"
    else
        echo "${var}=\"$value\"" >> "$CONFIG_FILE"
    fi
}

trap 'unset SWITCH_PASSWORD' EXIT
