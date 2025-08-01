# NetArtificer

**Version 2.5**

Artificers use ingenuity and magic to unlock extraordinary capabilities in ~~objects~~ network switches.

NetArtificer is a Bash-powered network toolkit for quick diagnostics, switch wrangling, and troubleshooting. It's menu-driven, works on Linux and macOS, and is mostly tested on Aruba switches (Cisco/Netgear support is there, but not guaranteed—I've only got Aruba gear to play with!).

## Why use NetArtificer?
- **Super Readable Output:** All results are color-coded, formatted, and organized for humans—not just dumped like raw CLI output. You get banners, tables, and clear prompts, so you always know what's going on.
- **User-Friendly Menus:** No need to memorize commands or flags. The interactive menus guide you through every step, with helpful warnings and confirmations.
- **Cleaner Than the CLI:** Instead of sifting through walls of text, NetArtificer highlights the important stuff and makes it easy to spot errors, warnings, and results at a glance.

## Features
- **Cable Diagnostics (TDR):** Run cable tests on supported switches (Aruba, Cisco, Netgear; Aruba is fully implemented).
- **VLAN Configuration Helper:** Interactive VLAN config for Aruba, Cisco, and Netgear switches, with LLDP auto-detection and safety checks.
- **LAG (Link Aggregation) Configuration:** Create and manage LAGs/port-channels on supported switches.
- **LLDP and ARP Info:** View detailed LLDP neighbor info (with option to hide Tailscale neighbors) and ARP tables.
- **Show Network Interfaces:** Lists all active interfaces, with type and speed, including bridge/AP status.
- **Access Point Control:** Enable/disable a Wi-Fi access point (bridged to Ethernet) with custom SSID/passphrase.
- **Network Utilities:**
  - Ping, Traceroute (MTR), DNS lookup, Port scan, Ping sweep
  - Wake-on-LAN, Speed test, WHOIS, SNMP monitoring
- **Settings Configuration:** Change SSH username, logging, log file, AP SSID/passphrase, and hide Tailscale LLDP neighbors—all from the menu.
- **Dependency Checking & Auto-Install:** Checks for all required tools and offers to install missing dependencies (supports apt and Homebrew).
- **Updater:** Checks for new versions on GitHub and can update itself in-place.
- **Logging:** Basic logging of actions to a configurable log file.
- **Command-Line Flags:** Run any tool directly with flags (e.g., `--ping`, `--vlan`, etc.) or use the interactive menu.
- **Extensible:** Drop new Bash scripts in the `tools/` folder to add your own menu options.
- **Cross-Platform:** Works on Linux and macOS (tested on both).
- **Safety:** Prompts and warnings to prevent accidental lockout or misconfiguration.
- **Quick Bailout:** Type `qq` at most prompts to return to the main menu.

## Planned Features
- More robust logging (log levels, filtering, better formatting)
- Fully tested Cisco and Netgear support
- Plugin/extension system for new tools
- Automatic menu generation from tools directory
- More output formatting and reporting
- Additional network utilities and vendor support

## Requirements
- Bash (Linux or macOS)
- Dependencies: lldpd, ssh, arp, awk, sed, grep, ping, dig, sshpass, wakeonlan, speedtest-cli, nmap, mtr, snmpget, whois
- If you're on macOS (with Homebrew) or Linux (with apt), missing dependencies are auto-installed for you!

## Installation
1. Clone this repo:
   ```sh
   git clone https://github.com/nathanakalish/netartificer.git
   cd netartificer
   ```
2. Make the main script executable:
   ```sh
   chmod +x netartificer.sh
   ```
3. Run it:
   ```sh
   sudo ./netartificer.sh
   ```
   (Root is needed for some network stuff.)

4. The script checks for dependencies and will offer to install anything missing.

## Usage
- Run with no arguments for the menu.
- Use `--help` for command-line options.
- You can type `qq` at most prompts to bail out to the main menu.

## Screenshots

Here are some screenshots of NetArtificer in action:

![Main Menu](screenshots/mainmenu.png)
![Cable Diagnostics](screenshots/cabletest.png)
![Port Scan](screenshots/portscan.png)
![LLDP Info](screenshots/lldp.png)

## Notes & Warnings
- **Cisco and Netgear support is experimental!** I only have Aruba switches to test on, so YMMV with other vendors.
- **Logging is pretty basic right now.** It appends to a log file, but doesn't log everything. I'll be making it more useful soon.
- No hardcoded secrets or passwords in the code. SSH creds are prompted and not saved.
- Log files/settings.conf might have sensitive info (like switch IPs/usernames). Don't upload those to public repos.
- You can add your own tools by dropping Bash scripts in the `tools/` folder.

## License
MIT License (see LICENSE)

## Disclaimer
Use at your own risk! This is a toolkit for network folks, but always test in a safe environment before using on production gear. If you break your network, that's on you :)
