#!/usr/bin/env bash
# 00-setup.sh: prva skripta. Instalira i podešava alate za vježbe u ovom repozitoriju.
# Podržano: Ubuntu 22.04/24.04 i Debian (i WSL2 Ubuntu). Pokretati kao običan korisnik (sudo se traži po potrebi).
#
#   ./00-setup.sh                  instalacija svega
#   SKIP_LIBVIRT=1 ./00-setup.sh   bez KVM/libvirt (vježba v2-p6, virtuelna mašina)
#   SKIP_CLAMAV=1 ./00-setup.sh    bez ClamAV-a (vježba v3-p2)
#
# Skripta je idempotentna: sigurno se može pokrenuti više puta.
set -euo pipefail

SKIP_LIBVIRT="${SKIP_LIBVIRT:-0}"
SKIP_CLAMAV="${SKIP_CLAMAV:-0}"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_step=$'\033[1;36m'; c_off=$'\033[0m'
step() { printf '\n%s== %s%s\n' "$c_step" "$*" "$c_off"; }
ok()   { printf '  %sok%s    %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!!%s    %s\n' "$c_warn" "$c_off" "$*"; }
have() { command -v "$1" >/dev/null 2>&1 || [ -x "/usr/sbin/$1" ] || [ -x "/sbin/$1" ]; }
apt_i() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$@"; }

[ "$(id -u)" -ne 0 ] || { echo "Ne pokretati kao root; skripta sama koristi sudo."; exit 1; }
[ "$(uname -s)" = "Linux" ] || { echo "Potreban je Linux ili WSL2."; exit 1; }
have apt-get || { echo "Skripta podržava samo apt (Ubuntu/Debian)."; exit 1; }
sudo -v

IN_WSL=0; grep -qi microsoft /proc/version 2>/dev/null && IN_WSL=1
HAS_SYSTEMD=0; [ "$(ps -p 1 -o comm= 2>/dev/null || true)" = "systemd" ] && HAS_SYSTEMD=1
NEED_RELOGIN=0

step "1/8 Provjera okruženja"
ok "$(. /etc/os-release && echo "$PRETTY_NAME")"
if [ "$IN_WSL" = 1 ]; then
  ok "WSL2 detektovan"
  if [ "$HAS_SYSTEMD" = 0 ]; then
    warn "systemd nije uključen (potreban za CUPS, servise u v3-p5 i libvirt)."
    if ! grep -qs '^\s*systemd\s*=\s*true' /etc/wsl.conf; then
      printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
      warn "dodano u /etc/wsl.conf. U PowerShellu pokrenuti: wsl --shutdown, pa ponovo otvoriti Ubuntu i ponovo ./00-setup.sh"
    fi
  fi
fi

step "2/8 Osnovni paketi (git, make, python3)"
sudo apt-get update -y -q
apt_i git make curl wget ca-certificates python3 python3-yaml openssh-client
ok "git, make, curl, python3"

step "3/8 Mreža (vježbe 1 i 2): iproute2, ping, traceroute, dig, dnsmasq, DHCP klijent, nftables"
# dnsmasq-base: samo program (bez sistemskog servisa koji bi zauzeo port 53); servisi se pokreću samo u labu
apt_i iproute2 iputils-ping iputils-tracepath traceroute bind9-dnsutils dnsmasq-base nftables netcat-openbsd curl
apt_i dhcpcd-base || apt_i dhcpcd5 || warn "DHCP klijent dhcpcd nije instaliran (v1-p1-lab ga traži)"
have netplan || apt_i netplan.io || warn "netplan nije instaliran (v1-p1-netplan tada provjerava samo YAML)"
ok "iproute2, ping, traceroute, dig, dnsmasq, dhcpcd, nftables"

step "4/8 Štampa (v2-p3): CUPS"
apt_i cups cups-client cups-bsd
if [ "$HAS_SYSTEMD" = 1 ]; then sudo systemctl enable --now cups >/dev/null 2>&1 || true; fi
# korisnik u grupi lpadmin smije upravljati štampačima bez sudo
case " $(id -nG "$USER") " in *" lpadmin "*) ;; *) sudo usermod -aG lpadmin "$USER"; NEED_RELOGIN=1 ;; esac
ok "cups"

step "5/8 Diskovi (v2-p4, v2-p5, v3-p3, v3-p4): mdadm, btrfs, particije, FAT, ext4"
# mdadm bez preporučenih paketa (inače povlači mail server)
apt_i --no-install-recommends mdadm
apt_i btrfs-progs fdisk parted dosfstools e2fsprogs util-linux
ok "mdadm, btrfs-progs, fdisk/sfdisk, dosfstools, e2fsprogs"

step "6/8 Održavanje OS-a (vježba 3): unattended-upgrades, ClamAV, sysstat"
apt_i unattended-upgrades sysstat procps
if [ "$SKIP_CLAMAV" = 1 ]; then warn "ClamAV preskočen (SKIP_CLAMAV=1)"
else
  apt_i clamav
  ok "clamav (službena baza potpisa se preuzima u pozadini servisom clamav-freshclam ili naredbom make v3-p2-apply)"
fi
ok "unattended-upgrades, sysstat (iostat)"

step "7/8 Virtuelne mašine (v2-p6): KVM, libvirt, virt-install"
if [ "$SKIP_LIBVIRT" = 1 ]; then
  warn "preskočeno (SKIP_LIBVIRT=1)"
else
  apt_i qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst libosinfo-bin
  for g in libvirt kvm; do
    case " $(id -nG "$USER") " in *" $g "*) ;; *) sudo usermod -aG "$g" "$USER"; NEED_RELOGIN=1 ;; esac
  done
  if [ "$HAS_SYSTEMD" = 1 ]; then
    sudo systemctl enable --now libvirtd
    V="sudo virsh -c qemu:///system"
    if ! $V pool-info default >/dev/null 2>&1; then
      $V pool-define-as default dir --target /var/lib/libvirt/images
      $V pool-autostart default
    fi
    $V pool-start default >/dev/null 2>&1 || true
    $V net-autostart default >/dev/null 2>&1 || true
    $V net-start default >/dev/null 2>&1 || true
    ok "libvirt radi, pool i mreža 'default' postoje"
  else
    warn "systemd nije aktivan: libvirt servis nije pokrenut"
  fi
  if [ -e /dev/kvm ]; then ok "/dev/kvm postoji"; else warn "nema /dev/kvm: v2-p6 ostaje na nivou plana"; fi
fi
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then ok "SSH ključ ~/.ssh/id_ed25519 postoji"
else mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" && ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@sima" && ok "napravljen ~/.ssh/id_ed25519"; fi

step "8/8 Provjera"
for t in git make python3 ip bridge ping traceroute dig dnsmasq dhcpcd nft lpadmin mdadm mkfs.btrfs sfdisk mkfs.vfat e4defrag clamscan iostat virsh virt-install qemu-img; do
  if have "$t"; then ok "$t"; else warn "$t nije instaliran"; fi
done
# jezgra: mogućnosti koje koriste labovi (WSL2 jezgra nema uvijek sve)
if sudo ip link add sima-test type bridge vlan_filtering 1 2>/dev/null; then sudo ip link del sima-test; ok "jezgra: bridge s VLAN filtriranjem (v1-p4)"
else warn "jezgra nema VLAN filtriranje na bridge-u: v1-p4-lab neće raditi"; fi
if [ -r /proc/mdstat ] || sudo modprobe raid1 2>/dev/null; then ok "jezgra: md RAID (v2-p4 koristi mdadm)"
else warn "jezgra nema md RAID: v2-p4 koristi btrfs RAID 1"; fi
grep -qw btrfs /proc/filesystems || sudo modprobe btrfs 2>/dev/null || warn "jezgra nema btrfs: v2-p4 i v3-p4 neće raditi"
true

printf '\n%sGotovo.%s Sljedeći koraci: make check, make help, make v1-p1\n' "$c_ok" "$c_off"
if [ "$NEED_RELOGIN" = 1 ]; then
  warn "Dodani ste u nove grupe (lpadmin/libvirt/kvm). Odjavite se i prijavite ponovo (WSL: wsl --shutdown)."
fi
