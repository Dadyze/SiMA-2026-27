#!/usr/bin/env bash
# v2/p4: softverski RAID 1 (ogledalo) na Linuxu: dva diska s istim podacima, kvar jednog diska, zamjena i obnova.
# Diskovi su datoteke prikačene kao loop uređaji, pa diskovi računara ostaju netaknuti.
#
# Alat: mdadm (Linux software RAID, ekvivalent "Mirrored Volume" u Windowsu). Ako jezgra nema md modul
# (npr. neke WSL2 jezgre), vježba se radi s btrfs RAID 1 (isti koraci: ogledalo, kvar, degradirani rad, zamjena).
# RAID_ALAT=btrfs ./raid1.sh vjezba   bira btrfs i kad mdadm radi.
#
#   ./raid1.sh pregled     postojeći RAID nizovi i diskovi na računaru (samo čita)
#   ./raid1.sh vjezba      RAID 1, upis podataka, kvar diska, rad bez jednog diska, zamjena i obnova (root)
#   ./raid1.sh down        otkači i obriši diskove vježbe
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
LAB=/var/tmp/sima-v2p4
MNT=/mnt/sima-raid
MD=/dev/md/sima-raid1

disk() { truncate -s 256M "$LAB/$1.img"; losetup -f --show "$LAB/$1.img"; }
loop_od() { losetup -j "$LAB/$1.img" | cut -d: -f1 | head -1; }
provjera_podataka() { if (cd "$MNT" && sha256sum -c --quiet "$LAB/kontrolni.sha256" 2>/dev/null); then ok "podaci su ispravni (sha256)"; else ne "podaci su oštećeni ili nedostupni"; fi; }

pregled() {
  korak "1. RAID nizovi (md) na računaru"
  if [ -r /proc/mdstat ]; then kmd cat /proc/mdstat; else info "nema /proc/mdstat: jezgra nema md modul ili niz još nije pravljen"; fi
  korak "2. Diskovi i particije (raid1 u koloni TYPE označava član ogledala)"
  kmd lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
}

izaberi_alat() {
  if [ "${RAID_ALAT:-}" = btrfs ]; then echo btrfs; return; fi
  if command -v mdadm >/dev/null && { [ -r /proc/mdstat ] || modprobe raid1 2>/dev/null; } && [ -r /proc/mdstat ]; then echo mdadm; else echo btrfs; fi
}

vjezba() {
  treba_root vjezba
  dolje >/dev/null 2>&1; mkdir -p "$LAB" "$MNT"
  local alat; alat="$(izaberi_alat)"
  korak "0. Alat: $alat"
  [ "$alat" = btrfs ] && info "md (mdadm) nije dostupan u ovoj jezgri: koristi se btrfs RAID 1 (koraci su isti)."
  treba "$( [ "$alat" = mdadm ] && echo mdadm || echo mkfs.btrfs )"

  korak "1. Dva nova diska od 256 MB (i treći kao zamjena za kasnije)"
  D1="$(disk disk1)"; D2="$(disk disk2)"; D3="$(disk disk3)"
  echo "   disk1=$D1  disk2=$D2  rezervni disk3=$D3"; pauza

  korak "2. Kreiranje RAID 1 polja (ogledalo): sve što se upiše, upiše se na oba diska"
  if [ "$alat" = mdadm ]; then
    kmd mdadm --create "$MD" --level=1 --raid-devices=2 --metadata=1.2 --run "$D1" "$D2"
    kmd mdadm --wait "$MD"
    kmd cat /proc/mdstat
    kmd mkfs.ext4 -q -L sima-raid "$MD"
    kmd mount "$MD" "$MNT"
  else
    kmd mkfs.btrfs -q -f -L sima-raid -d raid1 -m raid1 "$D1" "$D2"
    kmd mount "$D1" "$MNT"
    kmd btrfs filesystem show "$MNT"
    kmd btrfs filesystem df "$MNT"
  fi
  info "Kapacitet = kapacitet manjeg diska (polovina ukupnog prostora ide na kopiju)."
  kmd df -h "$MNT"; pauza

  korak "3. Upis podataka i kontrolni zbir (sha256) za kasniju provjeru"
  kmd dd if=/dev/urandom of="$MNT/baza.bak" bs=1M count=40 status=none
  echo "ugovor 2026-001" > "$MNT/ugovor.txt"
  (cd "$MNT" && sha256sum baza.bak ugovor.txt > "$LAB/kontrolni.sha256")
  sync; kmd ls -lh "$MNT"; provjera_podataka; pauza

  korak "4. Kvar diska 2: sistem i dalje radi s jednim diskom (degradirani rad)"
  if [ "$alat" = mdadm ]; then
    kmd mdadm "$MD" --fail "$D2"
    kmd cat /proc/mdstat
    info "[2/1] [U_]: od 2 diska radi 1. Polje je 'degraded', ali svi podaci su dostupni."
  else
    kmd umount "$MNT"
    kmd losetup -d "$D2"; info "(disk2 je 'izvađen': loop uređaj je otkačen)"
    kmd mount "$D1" "$MNT"
    info "Bez opcije degraded btrfs odbija montiranje kad disk nedostaje (zaštita od rada bez kopije):"
    kmd mount -o degraded "$D1" "$MNT"
    kmd btrfs filesystem show "$MNT"
  fi
  provjera_podataka
  echo "upis za vrijeme kvara" > "$MNT/novo.txt"; sync; pauza

  korak "5. Zamjena: izvaditi pokvareni disk, dodati novi; podaci se kopiraju na njega (rebuild/resync)"
  if [ "$alat" = mdadm ]; then
    kmd mdadm "$MD" --remove "$D2"
    kmd mdadm "$MD" --add "$D3"
    sleep 1; kmd cat /proc/mdstat
    kmd mdadm --wait "$MD"
    kmd mdadm --detail "$MD"
  else
    kmd btrfs replace start -B 2 "$D3" "$MNT"
    info "Blokovi upisani za vrijeme kvara su bez kopije (single); balance ih vraća u RAID 1:"
    kmd btrfs balance start -dconvert=raid1,soft -mconvert=raid1,soft "$MNT"
    kmd btrfs filesystem show "$MNT"
    kmd btrfs filesystem df "$MNT"
  fi
  provjera_podataka; pauza

  korak "6. RAID nije backup: obrisana datoteka je obrisana na OBA diska"
  kmd rm "$MNT/ugovor.txt"
  kmd ls "$MNT"
  info "RAID štiti od kvara diska, a ne od brisanja, ransomwarea ili požara: za to treba backup (kopija na drugom mjestu)."
  if [ "$alat" = mdadm ]; then
    korak "7. Trajna konfiguracija i nadzor (samo prikaz)"
    kmd mdadm --detail --scan
    info "Na pravom serveru ova linija ide u /etc/mdadm/mdadm.conf (pa update-initramfs -u), a mdadm --monitor šalje e-mail kod kvara."
  fi
}

dolje() {
  mountpoint -q "$MNT" && umount "$MNT"
  [ -e "$MD" ] && mdadm --stop "$MD" >/dev/null 2>&1
  local f l
  for f in "$LAB"/disk*.img; do
    [ -e "$f" ] || continue
    for l in $(losetup -j "$f" | cut -d: -f1); do
      command -v mdadm >/dev/null && mdadm --zero-superblock "$l" 2>/dev/null
      losetup -d "$l"
    done
  done
  command -v btrfs >/dev/null && btrfs device scan --forget 2>/dev/null
  rm -rf "$LAB"; rmdir "$MNT" 2>/dev/null; true
}

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: [RAID_ALAT=btrfs] $0 pregled | vjezba | down"; exit 1 ;; esac
