#!/usr/bin/env bash
# v2/p3: održavanje štampača na Linuxu (CUPS): instaliranje mrežnog štampača, štampa, red čekanja i zastoji.
# Mrežni štampač je emulator (emulator_stampaca.py) koji sluša na portu 9100 (RAW/JetDirect), pa ništa ne izlazi na papir.
#
#   ./stampac.sh pregled     štampači i redovi čekanja na ovom računaru (lpstat, ne traži root)
#   ./stampac.sh vjezba      dodaj štampač, štampaj, zastoj (štampač nedostupan, zaustavljen red), čišćenje reda (root)
#   ./stampac.sh down        uklanja štampač iz CUPS-a i gasi emulator
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
LAB=/var/tmp/sima-v2p3
STAMPAC=sima-stampac

emulator_gore() { python3 "$DIR/emulator_stampaca.py" "$LAB/izlaz" >> "$LAB/stampac.log" 2>&1 & echo $! > "$LAB/stampac.pid"; sleep 1; }
emulator_dolje() { [ -f "$LAB/stampac.pid" ] && kill "$(cat "$LAB/stampac.pid")" 2>/dev/null; rm -f "$LAB/stampac.pid"; sleep 1; }
cekaj_red() { local i; for i in $(seq 1 "${1:-15}"); do [ -z "$(lpstat -o "$STAMPAC" 2>/dev/null)" ] && return 0; sleep 1; done; return 1; }

cups_gore() {
  lpstat -r 2>/dev/null | grep -q 'is running' && return 0
  if [ "$(ps -p 1 -o comm=)" = systemd ]; then kmd systemctl start cups; else kmd cupsd; fi
  sleep 2; lpstat -r | grep -q 'is running' || { echo "CUPS ne radi (sudo systemctl status cups)"; exit 1; }
}

pregled() {
  korak "1. Da li radi CUPS (servis za štampu) i koji je zadani štampač"
  kmd lpstat -r; kmd lpstat -d
  korak "2. Svi štampači, njihovo stanje i redovi čekanja (lpstat -t)"
  kmd lpstat -t
  info "Upravljanje kroz preglednik: http://localhost:631 (CUPS web sučelje)."
}

vjezba() {
  treba_root vjezba; treba lpadmin; treba python3
  dolje >/dev/null 2>&1; mkdir -p "$LAB/izlaz"; : > "$LAB/stampac.log"
  korak "0. CUPS (Common UNIX Printing System) mora raditi"
  cups_gore

  korak "1. Mrežni štampač: uključen, ima statičku IP adresu i sluša na portu 9100 (RAW/JetDirect)"
  emulator_gore
  kmd ss -tlnp sport = :9100
  info "Mrežni štampač treba imati statičku IP adresu (u IP planu) i biti na žičnoj mreži, ne na Wi-Fi."; pauza

  korak "2. Instaliranje štampača: red čekanja u CUPS-u s adresom uređaja (device URI)"
  kmd lpadmin -p "$STAMPAC" -E -v socket://127.0.0.1:9100 -m raw -L "IT soba" -D "Mrežni štampač (lab)"
  info "(upozorenje o 'raw' redu je očekivano: pravi štampač dobija drajver, npr. -m everywhere za IPP Everywhere)"
  kmd lpstat -p "$STAMPAC" -l
  kmd lpstat -v "$STAMPAC"; pauza

  korak "3. Štampa: posao ide u red čekanja, a CUPS ga šalje štampaču"
  echo "Izvještaj o održavanju LAN mreže, $(date +%F)" > "$LAB/dokument.txt"
  kmd lp -d "$STAMPAC" -t "izvjestaj" "$LAB/dokument.txt"
  cekaj_red 10
  kmd cat "$LAB/stampac.log"
  kmd lpstat -W completed -o "$STAMPAC"; pauza

  korak "4. Zastoj: štampač je isključen ili nema mreže; poslovi ostaju u redu čekanja"
  emulator_dolje
  kmd lp -d "$STAMPAC" -t "faktura" "$LAB/dokument.txt"
  sleep 4
  kmd lpstat -p "$STAMPAC" -l
  kmd lpstat -o "$STAMPAC"
  info "Dijagnostika: ping adrese štampača, provjera porta (nc -zv adresa 9100), kabl, napajanje, papir/toner."; pauza

  korak "5. Otklanjanje: štampač je ponovo uključen; CUPS sam ponovo šalje posao"
  emulator_gore
  cekaj_red 40 && ok "red je prazan, posao je odštampan" || ne "posao još čeka"
  kmd tail -n1 "$LAB/stampac.log"; pauza

  korak "6. Zaglavljen red čekanja: red se pauzira, poslovi se gomilaju, brišu se i red se ponovo pokreće"
  kmd cupsdisable -r "održavanje štampača" "$STAMPAC"
  for t in ugovor ponuda narudzba; do kmd lp -d "$STAMPAC" -t "$t" "$LAB/dokument.txt"; done
  kmd lpstat -o "$STAMPAC"
  prvi="$(lpstat -o "$STAMPAC" | awk 'NR==1 {print $1}')"
  kmd cancel "$prvi"
  kmd lpstat -o "$STAMPAC"
  kmd cancel -a "$STAMPAC"
  kmd lpstat -o "$STAMPAC"
  kmd cupsenable "$STAMPAC"
  kmd lpstat -p "$STAMPAC"; pauza

  korak "7. Dijeljenje štampača u mreži (samo prikaz naredbi, ne izvršava se)"
  echo "  na računaru sa štampačem:   lpadmin -p $STAMPAC -o printer-is-shared=true && cupsctl --share-printers"
  echo "  na ostalim klijentima:      lpadmin -p $STAMPAC -E -v ipp://<adresa-servera>:631/printers/$STAMPAC -m everywhere"
  echo
  echo "Odštampani poslovi (izlaz emulatora): $LAB/izlaz/.  Čišćenje: make v2-p3-clean"
}

dolje() {
  lpstat -p "$STAMPAC" >/dev/null 2>&1 && { cancel -a "$STAMPAC" 2>/dev/null; lpadmin -x "$STAMPAC" && echo "uklonjen štampač $STAMPAC"; }
  emulator_dolje; rm -rf "$LAB"
}

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;; esac
