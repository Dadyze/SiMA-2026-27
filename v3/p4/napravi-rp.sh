#!/usr/bin/env bash
# v3/p4: pravi tačku vraćanja (read-only btrfs snapshot sistemskog subvolumena) i briše najstarije preko limita.
# Pokreće ga sima-restore-point.service (jednom dnevno preko .timer), a može i ručno ili prije instalacije programa.
#
#   napravi-rp.sh <btrfs-korijen> [opis]        npr. napravi-rp.sh /mnt/sima-btrfs prije-azuriranja
#   ZADRZI=7 (podrazumijevano): koliko tačaka vraćanja se čuva
set -euo pipefail
KORIJEN="${1:?Upotreba: $0 <btrfs-korijen> [opis]}"
OPIS="${2:-automatski}"
ZADRZI="${ZADRZI:-7}"

mkdir -p "$KORIJEN/.snapshots"
ime="RP-$(date +%Y%m%d-%H%M%S)-$OPIS"
# isto ime u istoj sekundi (više poziva zaredom): dodaje se redni broj
n=1; while [ -e "$KORIJEN/.snapshots/$ime" ]; do ime="RP-$(date +%Y%m%d-%H%M%S)-$OPIS-$n"; n=$((n + 1)); done
btrfs subvolume snapshot -r "$KORIJEN/@sistem" "$KORIJEN/.snapshots/$ime" >/dev/null
echo "napravljena tačka vraćanja: $ime"

# retencija: najstarije preko limita se brišu (redoslijed nastanka = ogen, generacija u kojoj je snapshot napravljen)
mapfile -t sve < <(btrfs subvolume list -s --sort=ogen "$KORIJEN" | awk '{print $NF}' | grep '^\.snapshots/RP-')
visak=$(( ${#sve[@]} - ZADRZI ))
for ((i = 0; i < visak; i++)); do
  btrfs subvolume delete "$KORIJEN/${sve[$i]}" >/dev/null && echo "obrisana stara tačka: ${sve[$i]#.snapshots/}"
done
