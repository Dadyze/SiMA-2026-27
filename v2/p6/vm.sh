#!/usr/bin/env bash
# v2/p6: instaliranje virtuelne mašine na Linuxu (KVM/QEMU + libvirt; Linux ekvivalent Hyper-V Managera).
# Umjesto interaktivne instalacije s ISO-a koristi se gotova Ubuntu cloud slika i cloud-init (korisnik, SSH ključ).
#
#   Hyper-V Manager (vježbe)                  Linux (virt-install / virsh)
#   1. instalacijski medij ili ISO            Ubuntu cloud slika (ili --cdrom ubuntu.iso za instalaciju s ISO-a)
#   2. New Virtual Machine                    virt-install
#   3. ime i lokacija                         --name sima-vm, disk u /var/lib/libvirt/images
#   4. RAM 1024 MB                            --memory 1024
#   5. mrežni adapter                         --network network=default (NAT mreža libvirt-a)
#   6. novi virtuelni disk                    qemu-img create ... 10G (qcow2: zauzima samo ono što je upisano)
#   7. pokreni VM nakon kreiranja             virt-install je pokreće sam
#   8. lokacija ISO-a                         --import (disk već sadrži sistem)
#   9. instalacija OS-a                       cloud-init pri prvom pokretanju (user-data)
#
#   ./vm.sh plan       provjera preduslova i ispis naredbi (ništa se ne pravi)
#   ./vm.sh up         preuzme sliku (~600 MB, jednom), napravi i pokrene VM, sačeka IP adresu (root, KVM)
#   ./vm.sh status     stanje VM-a i naredbe za upravljanje
#   ./vm.sh down       ugasi i obriše VM i njen disk (osnovna slika ostaje u kešu; SVE=1 briše i nju)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
IME=sima-vm
SLIKE=/var/lib/libvirt/images
URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
BAZA="$SLIKE/sima-noble-base.img"
DISK="$SLIKE/$IME.qcow2"
LAB=/var/tmp/sima-v2p6
V="virsh -c qemu:///system"
KORISNIK="${SUDO_USER:-$(id -un)}"
KLJUC="$(getent passwd "$KORISNIK" | cut -d: -f6)/.ssh/id_ed25519.pub"

# ubuntu24.04 ako ga poznaje osinfo baza (starije distribucije je nemaju), inače generička Linux postavka
os_id() { if osinfo-query os short-id=ubuntu24.04 2>/dev/null | grep -q ubuntu24.04; then echo ubuntu24.04; else echo generic; fi; }

naredba() {
  echo "virt-install --connect qemu:///system --name $IME --memory 1024 --vcpus 1 \\"
  echo "  --disk path=$DISK,format=qcow2 --import --osinfo $(os_id) \\"
  echo "  --network network=default --cloud-init user-data=$LAB/user-data --noautoconsole"
}

plan() {
  korak "Preduslovi"
  if [ -e /dev/kvm ]; then ok "/dev/kvm postoji (hardverska virtualizacija)"; else ne "nema /dev/kvm: VM se ne može pokrenuti (ostaje samo plan)"; fi
  if $V list >/dev/null 2>&1; then ok "libvirt radi"; else ne "libvirt ne radi (./00-setup.sh, README: systemd/KVM)"; fi
  $V net-info default 2>/dev/null | grep -q 'Active:.*yes' && ok "libvirt mreža 'default' je aktivna" || ne "mreža 'default' nije aktivna"
  command -v virt-install >/dev/null && ok "$(virt-install --version | sed 's/^/virt-install /')" || ne "nema virt-install"
  [ -f "$KLJUC" ] && ok "SSH ključ $KLJUC" || ne "nema $KLJUC (make ssh-key)"
  [ -f "$BAZA" ] && ok "osnovna slika je već preuzeta" || info "osnovna slika će se preuzeti (~600 MB): $URL"
  korak "Naredbe koje izvršava 'make v2-p6-up'"
  echo "qemu-img create -f qcow2 -F qcow2 -b $BAZA $DISK 10G"
  naredba
}

up() {
  treba_root up; treba virt-install; treba qemu-img
  $V list >/dev/null 2>&1 || { echo "libvirt ne radi: virsh -c qemu:///system list"; exit 1; }
  $V dominfo "$IME" >/dev/null 2>&1 && { echo "VM $IME već postoji (make v2-p6-clean)"; status; return 0; }
  [ -f "$KLJUC" ] || { echo "Nema SSH ključa $KLJUC: make ssh-key"; exit 1; }
  mkdir -p "$LAB" "$SLIKE"

  korak "1. Instalacijski medij: Ubuntu 24.04 cloud slika (preuzima se jednom)"
  [ -f "$BAZA" ] || kmd wget -q --show-progress -O "$BAZA" "$URL"
  kmd qemu-img info "$BAZA"
  korak "2. Virtuelni disk 10 GB (qcow2 s osnovnom slikom kao podlogom: zauzima samo razliku)"
  kmd qemu-img create -q -f qcow2 -F qcow2 -b "$BAZA" "$DISK" 10G
  korak "3. cloud-init: korisnik 'student' sa SSH ključem (umjesto interaktivne instalacije)"
  cat > "$LAB/user-data" <<EOF
#cloud-config
hostname: $IME
users:
  - name: student
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $(cat "$KLJUC")
EOF
  kmd cat "$LAB/user-data"
  korak "4. Kreiranje i pokretanje VM-a"
  echo "\$ $(naredba | tr -d '\\\n')"
  virt-install --connect qemu:///system --name "$IME" --memory 1024 --vcpus 1 \
    --disk "path=$DISK,format=qcow2" --import --osinfo "$(os_id)" \
    --network network=default --cloud-init "user-data=$LAB/user-data" --noautoconsole || exit 1
  korak "5. Čekanje na IP adresu iz DHCP-a libvirt mreže (do 2 minute)"
  local ip="" i
  for i in $(seq 1 60); do
    ip="$($V domifaddr "$IME" 2>/dev/null | awk '/ipv4/ {sub("/.*","",$4); print $4; exit}')"
    [ -n "$ip" ] && break; sleep 2
  done
  [ -n "$ip" ] && ok "VM ima adresu $ip" || ne "VM još nema adresu (sporo bez KVM-a); pokušati: make v2-p6-status"
  status
}

status() {
  korak "Stanje VM-a"
  kmd $V list --all
  kmd $V dominfo "$IME"
  kmd $V domifaddr "$IME"
  korak "Upravljanje (Hyper-V: Start, Turn Off, Shut Down, Checkpoint)"
  cat <<EOF
  ssh student@<IP>                                 prijava (IP iznad); cloud-init status --wait u VM-u čeka kraj podešavanja
  $V shutdown $IME                  uredno gašenje (Shut Down)
  $V destroy $IME                   "izvlačenje struje" (Turn Off)
  $V start $IME                     pokretanje
  $V snapshot-create-as $IME prije-azuriranja   kontrolna tačka (Checkpoint)
  $V snapshot-revert $IME prije-azuriranja      povratak na kontrolnu tačku
  virt-manager                                     grafičko sučelje (kao Hyper-V Manager)
EOF
}

down() {
  if $V dominfo "$IME" >/dev/null 2>&1; then
    $V destroy "$IME" >/dev/null 2>&1
    for s in $($V snapshot-list "$IME" --name 2>/dev/null); do $V snapshot-delete "$IME" "$s" >/dev/null; done
    $V undefine "$IME" >/dev/null && echo "obrisana VM $IME"
  fi
  rm -f "$DISK"; rm -rf "$LAB"
  [ "${SVE:-0}" = 1 ] && rm -f "$BAZA" && echo "obrisana osnovna slika"
  true
}

case "${1:-}" in plan) plan ;; up) up ;; status) status ;; down) down ;; *) echo "Upotreba: $0 plan | up | status | down"; exit 1 ;; esac
