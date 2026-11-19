#!/usr/bin/env bash
# v2/p5: particije diska (MBR i GPT), datotečni sistemi, UUID i fstab, boot opcije i bootabilni USB.
# "Disk" je datoteka od 1 GB prikačena kao loop uređaj, pa diskovi računara ostaju netaknuti.
#
#   ./particije.sh pregled     diskovi, tabele particija, UEFI/BIOS i boot opcije ovog računara (samo čita)
#   ./particije.sh vjezba      MBR tabela, pa GPT s EFI, sistemskom, particijom za podatke i recovery particijom (root)
#   ./particije.sh down        otkači i obriši disk vježbe
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SLIKA=/var/tmp/sima-v2p5-disk.img
MNT=/mnt/sima-particije

# particije loop uređaja: jezgra ih pravi kao /dev/loopNpM (losetup -P); partx osvježava ako ih nema
osvjezi() { partx -u "$1" 2>/dev/null; udevadm settle 2>/dev/null; sleep 1; }

pregled() {
  korak "1. Diskovi i particije: PTTYPE = tabela particija (dos = MBR, gpt = GPT)"
  kmd lsblk -o NAME,SIZE,TYPE,PTTYPE,FSTYPE,LABEL,MOUNTPOINTS
  korak "2. Firmware: UEFI (GPT + EFI particija) ili stari BIOS (MBR)"
  if [ -d /sys/firmware/efi ]; then echo "   UEFI"; command -v efibootmgr >/dev/null && kmd efibootmgr
  else echo "   BIOS (legacy) ili virtualno okruženje bez UEFI-ja (npr. WSL2)"; fi
  korak "3. Boot opcije s kojima je pokrenuta jezgra"
  kmd cat /proc/cmdline
  korak "4. Šta se montira pri pokretanju (/etc/fstab)"
  kmd grep -v '^#' /etc/fstab
}

vjezba() {
  treba_root vjezba; treba sfdisk; treba mkfs.vfat
  dolje >/dev/null 2>&1; mkdir -p "$MNT"
  korak "1. Novi prazan disk od 1 GB"
  kmd truncate -s 1G "$SLIKA"
  L="$(losetup -f --show -P "$SLIKA")"
  kmd lsblk -o NAME,SIZE,TYPE,PTTYPE "$L"; pauza

  korak "2. MBR (dos) tabela: najviše 4 primarne particije; za više se jedna pravi kao proširena (extended) s logičkim"
  info "MBR: zapis u prvom sektoru (512 B), diskovi do 2 TiB, BIOS boot. Raspored se zadaje skriptom za sfdisk:"
  cat > /tmp/sima-mbr.sfdisk <<'EOF'
label: dos
size=100MiB, type=83, bootable
size=300MiB, type=83
size=200MiB, type=82
type=5
size=150MiB, type=83
type=83
EOF
  sed 's/^/     /' /tmp/sima-mbr.sfdisk
  kmd sfdisk -q "$L" < /tmp/sima-mbr.sfdisk
  osvjezi "$L"
  kmd fdisk -l "$L"
  info "p1-p3 primarne (p1 je 'bootable' = aktivna particija za BIOS), p4 proširena, p5 i p6 logičke unutar nje; 82 = Linux swap."; pauza

  korak "3. GPT tabela (UEFI): do 128 particija, diskovi veći od 2 TiB, rezervna kopija tabele na kraju diska"
  cat > /tmp/sima-gpt.sfdisk <<'EOF'
label: gpt
size=100MiB, type=U, name="EFI"
size=500MiB, type=L, name="sistem"
size=250MiB, type=L, name="podaci"
type=L, name="recovery"
EOF
  sed 's/^/     /' /tmp/sima-gpt.sfdisk
  kmd wipefs -q -a "$L"
  kmd sfdisk -q "$L" < /tmp/sima-gpt.sfdisk
  osvjezi "$L"
  kmd fdisk -l "$L"
  info "EFI System Partition (ESP, FAT32) sadrži boot loader (npr. grubx64.efi ili Windows bootmgfw.efi):"
  info "to je Linux/UEFI ekvivalent Windows 'System Reserved' particije. Recovery particija služi za vraćanje sistema."; pauza

  korak "4. Datotečni sistemi: FAT32 za EFI, ext4 za sistem i podatke"
  kmd mkfs.vfat -F 32 -n EFI "${L}p1"
  kmd mkfs.ext4 -q -L sistem "${L}p2"
  kmd mkfs.ext4 -q -L podaci "${L}p3"
  kmd mkfs.ext4 -q -L recovery "${L}p4"
  kmd lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$L"; pauza

  korak "5. UUID: trajna oznaka datotečnog sistema (ime /dev/sdX se može promijeniti, UUID ne)"
  kmd blkid "${L}p1" "${L}p2" "${L}p3" "${L}p4"
  echo "   Linije za /etc/fstab (montiranje pri pokretanju, po UUID-u):"
  printf '     UUID=%-36s  /          ext4  errors=remount-ro  0 1\n' "$(blkid -s UUID -o value "${L}p2")"
  printf '     UUID=%-36s  /boot/efi  vfat  umask=0077         0 1\n' "$(blkid -s UUID -o value "${L}p1")"
  printf '     UUID=%-36s  /podaci    ext4  defaults           0 2\n' "$(blkid -s UUID -o value "${L}p3")"
  kmd mount "${L}p3" "$MNT"
  kmd df -hT "$MNT"
  kmd umount "$MNT"
  info "Preporuka: sistem na SSD-u, podaci na posebnom disku/particiji: reinstalacija sistema ne dira podatke."; pauza

  korak "6. Bootabilni USB (samo prikaz: dd briše cijeli odredišni disk!)"
  echo "   lsblk -o NAME,SIZE,MODEL,TRAN                                      # pronaći USB (TRAN = usb)"
  echo "   sudo dd if=ubuntu-24.04-desktop-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync"
  info "/dev/sdX je CIJELI USB disk (ne particija sdX1). Pogrešno slovo = izbrisan pogrešan disk."
}

dolje() {
  mountpoint -q "$MNT" && umount "$MNT"
  local l; for l in $(losetup -j "$SLIKA" 2>/dev/null | cut -d: -f1); do losetup -d "$l"; done
  rm -f "$SLIKA" /tmp/sima-mbr.sfdisk /tmp/sima-gpt.sfdisk; rmdir "$MNT" 2>/dev/null; true
}

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;; esac
