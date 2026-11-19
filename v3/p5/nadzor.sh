#!/usr/bin/env bash
# v3/p5: nadgledanje sistema i performansi (Windows: Task Manager) i upravljanje programima koji se pokreću sa sistemom
# (Windows: Startup aplikacije; Linux: systemd servisi i ~/.config/autostart).
#
#   Task Manager                 Linux
#   Processes                    top / htop, ps aux --sort=-%cpu
#   Performance (CPU, RAM, disk) uptime (load), free -h, vmstat, iostat
#   End task                     kill / pkill
#   Startup                      systemctl list-unit-files --state=enabled, systemd-analyze blame
#
#   ./nadzor.sh pregled     opterećenje, memorija, procesi, disk, servisi koji se pokreću sa sistemom (samo čita)
#   ./nadzor.sh vjezba      opterećenje CPU-a i pronalaženje "krivca", prioritet, gašenje procesa; servis pri startu (root)
#   ./nadzor.sh down        uklanja demo servis i gasi procese vježbe
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SERVIS=sima-demo
LAB=/run/sima-v3p5
ima_systemd() { [ "$(ps -p 1 -o comm=)" = systemd ]; }

pregled() {
  korak "1. Opterećenje (load average za 1, 5 i 15 minuta) i broj jezgri"
  kmd uptime; kmd nproc
  info "Load stalno veći od broja jezgri = procesi čekaju na CPU (sistem je preopterećen)."
  korak "2. Memorija (free -h): 'available' je stvarno slobodno; buff/cache jezgra oslobađa po potrebi"
  kmd free -h
  korak "3. Procesi koji najviše troše CPU i memoriju (ps)"
  kmd sh -c "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 6"
  kmd sh -c "ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n 6"
  korak "4. Trenutna slika kao u Task Manageru (top, jedan prolaz)"
  kmd sh -c "top -b -n1 | head -n 12"
  korak "5. CPU, memorija i disk kroz vrijeme (vmstat 1 3): r = procesi koji čekaju CPU, wa = čekanje na disk"
  kmd vmstat 1 3
  command -v iostat >/dev/null && { korak "6. Opterećenje diskova (iostat -x): %util blizu 100 = disk je usko grlo"; kmd sh -c "iostat -dxy 1 1 | awk '/^Device/ {p=1} p && NF && \$1 !~ /^loop/ {printf \"%-10s %8s %8s %7s\\n\", \$1, \$2, \$8, \$NF}'"; }
  korak "7. Šta se pokreće sa sistemom (Windows: Startup)"
  if ima_systemd; then
    kmd sh -c "systemctl list-unit-files --type=service --state=enabled --no-pager | head -n 20"
    kmd sh -c "systemd-analyze 2>/dev/null; systemd-analyze blame 2>/dev/null | head -n 8"
  else info "systemd nije aktivan (WSL bez systemd=true u /etc/wsl.conf): nema popisa servisa"; fi
  kmd ls "$HOME/.config/autostart" 2>/dev/null
  info "~/.config/autostart: programi grafičkog okruženja koji se pokreću nakon prijave korisnika."
}

vjezba() {
  treba_root vjezba
  dolje >/dev/null 2>&1; mkdir -p "$LAB"

  korak "1. Simulacija problema: 'zaglavljen' program troši cijelo jezgro procesora"
  (exec -a sima-zaglavljen sh -c 'while :; do :; done') & echo $! > "$LAB/zaglavljen.pid"
  sleep 3
  kmd uptime
  kmd sh -c "ps -eo pid,user,%cpu,%mem,etime,args --sort=-%cpu | head -n 4 | cut -c1-110"
  info "%cpu blizu 100 = jedno cijelo jezgro. Ovako se u Task Manageru (Processes, sortirano po CPU) traži krivac."; pauza

  korak "2. Prioritet: nice/renice (veći broj = manji prioritet), ostali programi dobijaju CPU prije njega"
  P="$(cat "$LAB/zaglavljen.pid")"
  kmd renice -n 19 -p "$P"
  kmd ps -o pid,ni,%cpu,args -p "$P"; pauza

  korak "3. Gašenje procesa (End task): kill šalje signal TERM (uredno), kill -9 KILL (prisilno)"
  kmd kill "$P"
  sleep 1
  kmd sh -c "ps -p $P >/dev/null && echo 'još radi' || echo 'proces je ugašen'"
  kmd pkill -f sima-nepostojeci; info "pkill/killall gase po imenu (izlazni kod 1 = nijedan proces nije pronađen)."; pauza

  if ! ima_systemd; then
    info "systemd nije aktivan: dio s automatskim pokretanjem se preskače (WSL: systemd=true u /etc/wsl.conf)."; return 0
  fi
  korak "4. Program koji se pokreće sa sistemom: systemd servis (enable = Startup 'Enabled')"
  kmd install -m 644 "$DIR/$SERVIS.service" "/etc/systemd/system/$SERVIS.service"
  kmd systemctl daemon-reload
  kmd systemctl enable --now "$SERVIS"
  kmd systemctl is-enabled "$SERVIS"
  kmd systemctl status "$SERVIS" --no-pager -n 3
  sleep 1; kmd journalctl -u "$SERVIS" --no-pager -n 3; pauza

  korak "5. Isključivanje iz pokretanja (Startup 'Disabled'): disable; --now ga i zaustavlja"
  kmd systemctl disable --now "$SERVIS"
  kmd systemctl is-enabled "$SERVIS"
  kmd systemctl is-active "$SERVIS"
  info "Brže pokretanje: systemd-analyze blame pokazuje koji servisi najduže traju; nepotrebni se isključuju (disable)."
}

dolje() {
  [ -f "$LAB/zaglavljen.pid" ] && kill "$(cat "$LAB/zaglavljen.pid")" 2>/dev/null
  pkill -f sima-zaglavljen 2>/dev/null
  if [ -f "/etc/systemd/system/$SERVIS.service" ]; then
    systemctl disable --now "$SERVIS" 2>/dev/null; rm -f "/etc/systemd/system/$SERVIS.service"; systemctl daemon-reload 2>/dev/null
    echo "uklonjen servis $SERVIS"
  fi
  rm -rf "$LAB"; true
}

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: $0 pregled | vjezba | down"; exit 1 ;; esac
