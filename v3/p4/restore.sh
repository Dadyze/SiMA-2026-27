#!/usr/bin/env bash
# v3/p4: tačka vraćanja (Windows: Restore Point / System Protection). Na Linuxu: snapshot datotečnog sistema
# (btrfs; isto rade Timeshift i Snapper). Sistem i korisnički podaci su u odvojenim subvolumenima, pa se vraćanjem
# sistema vraćaju sistemske datoteke i programi, a podaci korisnika NE (isto kao Windows Restore Point).
# Sve se radi na disku-datoteci (loop) s btrfs-om, pa sistem računara ostaje netaknut.
#
#   btrfs disk:  @sistem  (u praksi /: /etc, /usr ...)    @home  (u praksi /home)    .snapshots/RP-...  (tačke vraćanja)
#
#   ./restore.sh vjezba     tačka vraćanja, "loša instalacija", vraćanje, automatske tačke i retencija (root)
#   ./restore.sh provjera   provjera systemd timera iz repozitorija (systemd-analyze, ništa se ne instalira)
#   ./restore.sh down       otkači i obriši disk vježbe
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SLIKA=/var/tmp/sima-v3p4-btrfs.img
K=/mnt/sima-btrfs

stanje() {
  printf '   %-34s %s\n' "verzija programa (sistem):" "$(cat "$K/@sistem/usr/bin/aplikacija")"
  printf '   %-34s %s\n' "konfiguracija (sistem):" "$(cat "$K/@sistem/etc/aplikacija.conf")"
  printf '   %-34s %s\n' "dokumenti korisnika (podaci):" "$(ls "$K/@home/student" | tr '\n' ' ')"
}

vjezba() {
  treba_root vjezba; treba mkfs.btrfs
  dolje >/dev/null 2>&1
  korak "1. Disk s btrfs-om: subvolumen @sistem (programi, postavke) i @home (podaci korisnika)"
  truncate -s 512M "$SLIKA"; mkfs.btrfs -q -f -L sima-sistem "$SLIKA"
  mkdir -p "$K"; mount -o loop "$SLIKA" "$K"
  kmd btrfs subvolume create "$K/@sistem"
  kmd btrfs subvolume create "$K/@home"
  mkdir -p "$K/@sistem/etc" "$K/@sistem/usr/bin" "$K/@home/student"
  echo "1.0 (radi)" > "$K/@sistem/usr/bin/aplikacija"
  echo "port=80" > "$K/@sistem/etc/aplikacija.conf"
  echo "uvod" > "$K/@home/student/diplomski-poglavlje1.txt"
  stanje; pauza

  korak "2. Tačka vraćanja prije instalacije: read-only snapshot sistema (trenutno, zauzima prostor tek kad se sistem mijenja)"
  kmd bash "$DIR/napravi-rp.sh" "$K" prije-instalacije
  kmd btrfs subvolume list "$K"; pauza

  korak "3. Instalacija novog programa pokvari sistem; u međuvremenu korisnik piše nove podatke"
  echo "2.0 (NE RADI: ruši se pri pokretanju)" > "$K/@sistem/usr/bin/aplikacija"
  echo "port=GRESKA" > "$K/@sistem/etc/aplikacija.conf"
  echo "rezultati" > "$K/@home/student/diplomski-poglavlje2.txt"
  stanje; pauza

  korak "4. Vraćanje sistema na tačku vraćanja (System Restore)"
  RP="$(ls -1 "$K/.snapshots" | grep prije-instalacije | tail -n1)"
  kmd mv "$K/@sistem" "$K/@sistem-pokvaren"
  kmd btrfs subvolume snapshot "$K/.snapshots/$RP" "$K/@sistem"
  kmd btrfs subvolume delete "$K/@sistem-pokvaren"
  stanje
  info "Sistem (program i postavke) je vraćen, a novo poglavlje u @home je ostalo: tačka vraćanja ne dira podatke."
  info "Na pravom računaru @sistem je montiran kao /, pa se vraćanje radi iz Timeshifta/Snappera i završava restartom."; pauza

  korak "5. Automatske tačke vraćanja: dnevno (systemd timer) i prije promjene sistema; čuva se zadnjih 7"
  kmd cat "$DIR/sima-restore-point.timer"
  echo "\$ for i in 1..8: ZADRZI=7 napravi-rp.sh $K automatski"
  for i in $(seq 1 8); do ZADRZI=7 bash "$DIR/napravi-rp.sh" "$K" automatski; done | sed 's/^/   /'
  kmd sh -c "btrfs subvolume list -s --sort=ogen $K | awk '{print \$NF}' | grep snapshots"
  info "Windows pravi RP prije instalacije i sedmično; na Ubuntuu to rade npr. Timeshift (zakazano) ili snapper + apt (prije svake instalacije)."
  kmd umount "$K"
}

provjera() {
  korak "systemd timer za automatske tačke vraćanja"
  if command -v systemd-analyze >/dev/null; then
    kmd systemd-analyze calendar daily
    T="$(mktemp -d)"; cp "$DIR"/sima-restore-point.{service,timer} "$T/"
    sed -i "s|/usr/local/sbin/napravi-rp.sh|$DIR/napravi-rp.sh|" "$T/sima-restore-point.service"
    if systemd-analyze verify "$T/sima-restore-point.timer" "$T/sima-restore-point.service" 2>&1 | grep -v -i 'not executable\|is marked' ; then :; fi
    ok "unit datoteke su provjerene (systemd-analyze verify)"; rm -rf "$T"
  else info "systemd-analyze nije dostupan"; fi
  kmd bash -n "$DIR/napravi-rp.sh" && ok "napravi-rp.sh: sintaksa ispravna"
}

dolje() {
  mountpoint -q "$K" && umount "$K"
  local l; for l in $(losetup -j "$SLIKA" 2>/dev/null | cut -d: -f1); do losetup -d "$l"; done
  rm -f "$SLIKA"; rmdir "$K" 2>/dev/null; true
}

case "${1:-}" in vjezba) vjezba ;; provjera) provjera ;; down) dolje ;; *) echo "Upotreba: $0 vjezba | provjera | down"; exit 1 ;; esac
