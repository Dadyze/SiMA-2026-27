#!/usr/bin/env bash
# v3/p1: održavanje klijentskog OS-a: ažuriranje sistema (ručno i automatizirano). Windows: Windows Update;
# Linux (Ubuntu/Debian): apt za ručno ažuriranje, unattended-upgrades za automatske sigurnosne zakrpe.
#
#   ./azuriranje.sh pregled     verzija sistema, dostupna ažuriranja, postavke automatskog ažuriranja, historija (samo čita)
#   ./azuriranje.sh provjera    provjera konfiguracijskih datoteka iz ovog direktorija (apt-config, ništa se ne mijenja)
#   ./azuriranje.sh apply       apt update, simulacija ažuriranja, uključivanje automatskog ažuriranja, probni prolaz (root)
#   ./azuriranje.sh down        uklanja postavke koje je dodao apply
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
CONF=/etc/apt/apt.conf.d

pregled() {
  korak "1. Verzija sistema i jezgre"
  kmd grep PRETTY_NAME /etc/os-release
  kmd uname -r
  korak "2. Kada je zadnji put osvježen popis paketa (apt update)"
  local zadnji; zadnji="$(ls -t /var/lib/apt/lists/*Release 2>/dev/null | head -n 1)"
  if [ -n "$zadnji" ]; then echo "   $(date -r "$zadnji" '+%F %T')"; else ne "popis paketa nikad nije preuzet"; fi
  info "Popis je lokalni keš: bez 'apt update' sistem ne zna za nova ažuriranja."
  korak "3. Dostupna ažuriranja (iz keša) i koja su sigurnosna"
  local n s
  n="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst')"
  s="$(apt-get -s upgrade 2>/dev/null | grep '^Inst' | grep -ci security)"
  echo "   paketa za ažuriranje: $n   od toga sigurnosnih: $s"
  kmd sh -c "apt list --upgradable 2>/dev/null | head -n 11"
  korak "4. Automatsko ažuriranje (unattended-upgrades)"
  if dpkg -s unattended-upgrades >/dev/null 2>&1; then ok "unattended-upgrades je instaliran"; else ne "unattended-upgrades nije instaliran"; fi
  kmd sh -c "apt-config dump | grep -E '^APT::Periodic::|^Unattended-Upgrade::Automatic-Reboot'"
  [ "$(ps -p 1 -o comm=)" = systemd ] && kmd systemctl list-timers 'apt-daily*' --no-pager
  korak "5. Treba li restart (nova jezgra ili sistemske biblioteke)"
  if [ -f /var/run/reboot-required ]; then ne "potreban je restart:"; cat /var/run/reboot-required.pkgs 2>/dev/null | sed 's/^/     /'
  else ok "restart nije potreban"; fi
  korak "6. Historija ažuriranja (zadnja 3 izvršavanja apt-a)"
  kmd sh -c "grep -E '^(Start-Date|Commandline|Upgrade)' /var/log/apt/history.log 2>/dev/null | tail -n 9 | cut -c1-160"
}

provjera() {
  korak "Konfiguracija automatskog ažuriranja iz repozitorija (apt-config čita datoteku, ništa se ne primjenjuje)"
  local f
  for f in 20auto-upgrades 52sima-unattended-upgrades; do
    echo "--- $f"
    if apt-config -c "$DIR/$f" dump >/dev/null 2>&1; then
      apt-config -c "$DIR/$f" dump | grep -E '^(APT::Periodic::[A-Z]|Unattended-Upgrade::[A-Z])' | sed 's/^/   /'; ok "$f je ispravan"
    else ne "$f ima grešku"; apt-config -c "$DIR/$f" dump 2>&1 | tail -2; fi
  done
}

apply() {
  treba_root apply
  korak "1. Osvježavanje popisa paketa (apt update)"
  kmd apt-get update -q
  korak "2. Simulacija ažuriranja (-s: prikazuje šta bi se uradilo, ništa ne mijenja)"
  kmd sh -c "apt-get -s upgrade | grep -E '^Inst' | head -n 15; apt-get -s upgrade | tail -n 1"
  info "Stvarno ažuriranje: sudo apt upgrade (ili full-upgrade, koji smije i ukloniti/dodati pakete zbog zavisnosti)."
  korak "3. Uključivanje automatskih sigurnosnih ažuriranja"
  kmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -q unattended-upgrades
  kmd install -m 644 "$DIR/20auto-upgrades" "$CONF/20auto-upgrades"
  kmd install -m 644 "$DIR/52sima-unattended-upgrades" "$CONF/52sima-unattended-upgrades"
  kmd sh -c "apt-config dump | grep -E '^APT::Periodic::|^Unattended-Upgrade::(Automatic|Remove)'"
  korak "4. Probni prolaz (--dry-run): koje bi pakete automatsko ažuriranje sada instaliralo"
  kmd sh -c "unattended-upgrade --dry-run -v 2>&1 | grep -E 'Allowed origins|Packages that will be upgraded|No packages found|rror' | cut -c1-200 | head -n 5"
  info "Zapisnik automatskih ažuriranja: /var/log/unattended-upgrades/unattended-upgrades.log"
}

down() {
  treba_root down
  rm -f "$CONF/52sima-unattended-upgrades" && echo "uklonjen $CONF/52sima-unattended-upgrades"
  info "$CONF/20auto-upgrades je ostavljen: to je standardna datoteka paketa unattended-upgrades (isključivanje: vrijednosti \"0\")."
}

case "${1:-}" in pregled) pregled ;; provjera) provjera ;; apply) apply ;; down) down ;;
  *) echo "Upotreba: $0 pregled | provjera | apply | down"; exit 1 ;; esac
