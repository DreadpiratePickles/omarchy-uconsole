#!/bin/bash
# A lean, standard security toolkit. Everything here is in the official Arch
# repositories; this is not the full Kali metapackage.
LOG=/tmp/sectools.log
: > "$LOG"
while pgrep -x pacman >/dev/null; do sleep 15; done

PKGS="nmap rustscan masscan tcpdump wireshark-cli termshark arp-scan bind
traceroute mtr openbsd-netcat aircrack-ng hcxtools hcxdumptool macchanger iw
wifite reaver nikto sqlmap gobuster hydra hashcat binwalk radare2 strace ltrace
foremost testdisk tor torsocks proxychains-ng openvpn wireguard-tools
perl-image-exiftool exploitdb"

sudo pacman -S --needed --noconfirm $PKGS >>"$LOG" 2>&1
echo "EXIT=$?" >> "$LOG"
