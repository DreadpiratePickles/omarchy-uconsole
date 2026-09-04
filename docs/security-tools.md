# Security tooling

A lean toolkit for a uConsole cyberdeck. Everything here is a standard package in
the official Arch Linux ARM repositories — this is not the Kali metapackage, and
it is not thousands of tools you will never open on a 5 inch screen.

```bash
sudo pacman -S --needed $(tr '\n' ' ' < scripts/security-packages.txt)
```

## What you get

| Area | Tools |
|---|---|
| Scanning | `nmap`, `rustscan`, `masscan`, `arp-scan` |
| Traffic | `tcpdump`, `wireshark-cli` (`tshark`), `termshark` |
| Wireless | `aircrack-ng`, `hcxtools`, `hcxdumptool`, `wifite`, `reaver`, `macchanger`, `iw` |
| Web | `nikto`, `sqlmap`, `gobuster` |
| Credentials | `hydra`, `hashcat` |
| Reversing | `radare2`, `binwalk`, `strace`, `ltrace` |
| Forensics | `foremost`, `testdisk`, `perl-image-exiftool` |
| Privacy | `tor`, `torsocks`, `proxychains-ng`, `openvpn`, `wireguard-tools` |
| Exploits | `exploitdb` (`searchsploit`) |
| Network basics | `bind` (`dig`), `traceroute`, `mtr`, `openbsd-netcat` |

## exiftool is not on your PATH

Arch installs it into a Perl vendor directory that is not searched by default:

```bash
sudo ln -sf /usr/bin/vendor_perl/exiftool /usr/local/bin/exiftool
```

## Not available for aarch64

`ffuf`, `dirb`, `john` and `seclists` have no ARM package in the official repos.
Build them from the AUR if you want them.

## Pairs well with the AIO V2

If you have the expansion board, the SDR and GPS tooling from
[aio-v2.md](aio-v2.md) complements this: `rtl-sdr`, `soapysdr`, `gpsd`. The board's
RTL-SDR works fully on ARM.

## Note on hashcat

The CM4's VideoCore GPU has no OpenCL support worth using, so `hashcat` runs on
CPU only. Four Cortex-A72 cores is not a cracking rig. Treat it as a tool for
learning and small workloads, not throughput.
