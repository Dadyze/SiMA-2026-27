#!/usr/bin/env bash
# v3/p3: održavanje tvrdog diska: šta zauzima prostor, automatsko čišćenje (Storage Sense), fragmentacija i
# defragmentacija (HDD) te TRIM (SSD). Fragmentacija se radi na disku-datoteci (loop), pa disk računara ostaje netaknut.
#
#   ./disk.sh pregled     zauzeće diska, najveći direktoriji, dnevnici, keš paketa (samo čita)
#   ./disk.sh vjezba      čišćenje starih datoteka, fragmentacija i defragmentacija, TRIM (root)   PAUZA=1 čeka Enter
#   ./disk.sh down        briše datoteke vježbe
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SLIKA=/var/tmp/sima-v3p3-disk.img
MNT=/mnt/sima-hdd
TEMP=/var/tmp/sima-temp

pregled() {
  korak "1. Zauzeće datotečnih sistema (df -h): prvo se gleda Use%"
  kmd df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay
  korak "2. Najveći direktoriji u home direktoriju (du)"
  kmd sh -c "du -xh --max-depth=1 \"\$HOME\" 2>/dev/null | sort -h | tail -n 8"
  korak "3. Tipični 'potrošači' prostora koji se mogu čistiti"
  printf '   %-36s %s\n' "keš preuzetih paketa (apt clean)" "$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)"
  printf '   %-36s %s\n' "sistemski dnevnici (journald)" "$(journalctl --disk-usage 2>/dev/null | grep -o '[0-9.]*[KMGT]\?B\?' | head -n1)"
  printf '   %-36s %s\n' "keš aplikacija (~/.cache)" "$(du -sh "$HOME/.cache" 2>/dev/null | cut -f1)"
  printf '   %-36s %s\n' "kanta za smeće (~/.local/share/Trash)" "$(du -sh "$HOME/.local/share/Trash" 2>/dev/null | cut -f1)"
  printf '   %-36s %s\n' "privremene datoteke (/var/tmp)" "$(du -sh /var/tmp 2>/dev/null | cut -f1)"
  korak "4. Naredbe za čišćenje (samo prikaz)"
  echo "   sudo apt clean                          # briše keš preuzetih paketa"
  echo "   sudo apt autoremove                     # uklanja pakete koji više nisu potrebni (i stare jezgre)"
  echo "   sudo journalctl --vacuum-time=14d       # briše dnevnike starije od 14 dana"
  echo "   rm -rf ~/.cache/*  ;  gio trash --empty  # keš aplikacija i kanta za smeće"
}

vjezba() {
  treba_root vjezba; treba e4defrag; treba filefrag
  dolje >/dev/null 2>&1

  korak "1. 'Storage Sense' na Linuxu: systemd-tmpfiles briše privremene datoteke starije od zadate starosti"
  mkdir -p "$TEMP"
  for i in 1 2 3; do echo "stari izvještaj $i" > "$TEMP/stari-$i.tmp"; touch -d "$((i * 5 + 5)) days ago" "$TEMP/stari-$i.tmp"; done
  echo "današnji rad" > "$TEMP/novi.tmp"
  kmd ls -l --time-style=+%F "$TEMP"
  kmd cat "$DIR/sima-ciscenje.conf"
  local verzija; verzija="$(systemd-tmpfiles --version 2>/dev/null | awk 'NR==1 {print $2}')"
  if [ "${verzija:-0}" -ge 250 ] 2>/dev/null; then
    kmd systemd-tmpfiles --clean "$DIR/sima-ciscenje.conf"
  else
    info "systemd $verzija ne podržava 'm:' u starosti; isti efekat ima find:"
    kmd find "$TEMP" -type f -mtime +7 -delete
  fi
  kmd ls -l --time-style=+%F "$TEMP"
  [ "$(ps -p 1 -o comm=)" = systemd ] && kmd systemctl list-timers systemd-tmpfiles-clean.timer --no-pager
  info "Na pravom sistemu: datoteka u /etc/tmpfiles.d/ i čišćenje jednom dnevno (systemd-tmpfiles-clean.timer)."; pauza

  korak "2. Fragmentacija: disk od 128 MB (ext4), dvije datoteke se pišu naizmjenično u komadima od 64 KB"
  truncate -s 128M "$SLIKA"; mkfs.ext4 -q -L sima-hdd "$SLIKA"
  L="$(losetup -f --show "$SLIKA")"; mkdir -p "$MNT"; mount "$L" "$MNT"
  echo "\$ for i in 1..64: dopiši 64 KB u izvjestaj.dat, sync; dopiši 64 KB u baza.dat, sync"
  for i in $(seq 1 64); do
    for f in izvjestaj.dat baza.dat; do
      dd if=/dev/urandom of="$MNT/$f" bs=64K count=1 oflag=append conv=notrunc status=none; sync "$MNT/$f"
    done
  done
  kmd filefrag "$MNT/izvjestaj.dat" "$MNT/baza.dat"
  info "extent = niz susjednih blokova. 64 extenta znači da je datoteka u 64 komada razbacanih po disku:"
  info "na HDD-u glava za čitanje mora skakati između komada, pa je čitanje sporije."
  kmd e4defrag -c "$MNT"; pauza

  korak "3. Defragmentacija (e4defrag): dijelovi datoteke se slažu u susjedne blokove"
  kmd e4defrag "$MNT/izvjestaj.dat"
  kmd filefrag "$MNT/izvjestaj.dat" "$MNT/baza.dat"
  info "ext4 i drugi Linux datotečni sistemi pri normalnom radu malo fragmentiraju (odgođena alokacija),"
  info "pa se defragmentacija rijetko radi ručno; na Windowsu je to zadatak 'Defragment and Optimize Drives'."; pauza

  korak "4. SSD: ne defragmentira se (nema glave koja se pomjera, a upis troši ćelije); radi se TRIM"
  kmd fstrim -v "$MNT"
  info "TRIM javlja SSD-u koji su blokovi slobodni. Ubuntu ga radi sedmično: systemctl status fstrim.timer"
  kmd umount "$MNT"; losetup -d "$L"
}

dolje() {
  mountpoint -q "$MNT" && umount "$MNT"
  local l; for l in $(losetup -j "$SLIKA" 2>/dev/null | cut -d: -f1); do losetup -d "$l"; done
  rm -rf "$SLIKA" "$TEMP"; rmdir "$MNT" 2>/dev/null; true
}

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;; esac
