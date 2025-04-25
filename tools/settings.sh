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
    echo -e "${BLUE}0)${NC} Go Back"
    echo ""
}

# Menu for editing NetArtificer configuration settings.
configure_settings() {
    show_banner
    echo -e "${BLUE}Settings Configuration:${NC}"
    while true; do
        print_settings_menu
        read -e -rp "Choice: " setting_choice
        case $setting_choice in
            1)
                show_banner
                while true; do
                    [ -n "$invalid_user_msg" ] && echo -e "${RED}$invalid_user_msg${NC}"
                    read -e -rp "Enter new default SSH Username: " new_user
                    [ "$new_user" = "qq" ] && break
                    if [[ -n "$new_user" && "$new_user" =~ ^[a-zA-Z0-9._-]+$ ]]; then
                        sed -i '' "s/^SSH_USER=.*/SSH_USER=\"$new_user\"/" "$CONFIG_FILE"
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
                    sed -i '' "s/^LOGGING=.*/LOGGING=\"$new_logging\"/" "$CONFIG_FILE"
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
                        sed -i '' "s/^LOG_FILENAME=.*/LOG_FILENAME=\"$new_log\"/" "$CONFIG_FILE"
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

trap 'unset SWITCH_PASSWORD' EXIT
