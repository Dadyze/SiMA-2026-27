#!/usr/bin/env bash
# v2/p1: održavanje LAN mreže: CLI naredbe za dijagnosticiranje (Linux ekvivalenti Windows naredbi) i traženje kvara.
#
#   Windows            Linux
#   ping               ping (bez -c šalje beskonačno; Ctrl+C prekida)
#   ipconfig [/all]    ip addr, ip route, resolvectl / cat /etc/resolv.conf
#   tracert            traceroute / tracepath
#   netstat -a -n      ss -tan  (netstat -an iz paketa net-tools i dalje postoji, ali je zastario)
#
#   [pc] 192.168.20.50 --- [ruter] 192.168.20.1 / 203.0.113.2 --- [internet] web klix.ba 198.51.100.10, DNS 198.51.100.53
#
#   ./dijagnostika.sh vjezba           sve naredbe redom na ispravnoj mreži (root)
#   ./dijagnostika.sh kvar [1-6]       ubaci kvar (bez broja: slučajan, skriven), pa ga treba pronaći
#   ./dijagnostika.sh dijagnoza        dijagnostika "odozdo prema gore": link, adresa, gateway, IP, DNS, servis
#   ./dijagnostika.sh rjesenje         otkriva koji je kvar ubačen i vraća ispravno stanje
#   ./dijagnostika.sh down             briše lab
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SVI="sima-pc sima-ruter sima-inet"
LAB=/run/sima-v2p1
KVAROVI=(
  ""
  "kabl: kabl između računara i sviča/rutera je prekinut (nema linka)"
  "pogrešan gateway: računar šalje promet za druge mreže na adresu koja ne postoji"
  "DNS: zadan je DNS server koji ne postoji (IP radi, imena ne)"
  "pogrešna adresa: računar je ručno dobio adresu iz druge podmreže"
  "servis: web server ne radi (mreža je ispravna, ali aplikacija nije dostupna)"
  "ruter: ruter ne prosljeđuje pakete (ip_forward=0)"
)

lab_gore() {
  ip netns list | grep -qw sima-pc && return 0
  mkdir -p "$LAB/www" /etc/netns/sima-pc
  echo "<h1>klix.ba (lab)</h1>" > "$LAB/www/index.html"
  for ns in $SVI; do ns_novi "$ns"; done
  veza sima-pc eth0 sima-ruter lan
  veza sima-ruter wan sima-inet eth0
  ip -n sima-ruter addr add 192.168.20.1/24 dev lan; ip -n sima-ruter addr add 203.0.113.2/30 dev wan
  ip -n sima-ruter route add default via 203.0.113.1
  ip -n sima-inet addr add 203.0.113.1/30 dev eth0; ip -n sima-inet route add 192.168.20.0/24 via 203.0.113.2
  ip -n sima-inet addr add 198.51.100.10/32 dev lo; ip -n sima-inet addr add 198.51.100.53/32 dev lo
  ip netns exec sima-inet dnsmasq --conf-file=/dev/null --pid-file="$LAB/dns.pid" --listen-address=198.51.100.53 \
    --bind-interfaces --no-resolv --no-hosts --address=/klix.ba/198.51.100.10
  web_gore
  ispravno
}
web_gore() { ip netns exec sima-inet python3 -m http.server 80 --bind 198.51.100.10 --directory "$LAB/www" >/dev/null 2>&1 & echo $! > "$LAB/web.pid"; sleep 1; }

# ispravno: vraća sve što kvarovi mijenjaju u ispravno stanje
ispravno() {
  ip -n sima-ruter link set lan up
  ip -n sima-pc addr flush dev eth0; ip -n sima-pc addr add 192.168.20.50/24 dev eth0
  ip -n sima-pc route replace default via 192.168.20.1
  echo "nameserver 198.51.100.53" > /etc/netns/sima-pc/resolv.conf
  ip netns exec sima-ruter sysctl -qw net.ipv4.ip_forward=1
  kill -0 "$(cat "$LAB/web.pid" 2>/dev/null)" 2>/dev/null || web_gore
  rm -f "$LAB/kvar"
}

vjezba() {
  treba_root vjezba; treba dnsmasq; treba traceroute; treba dig; treba curl
  dolje >/dev/null 2>&1; lab_gore

  korak "1. ping 127.0.0.1: loopback (samoprozivka). Ne odgovara = TCP/IP na računaru ne radi"
  kmd sima-pc ping -c2 127.0.0.1; pauza
  korak "2. ip addr / ip route / resolv.conf: Linux 'ipconfig /all' (adresa, maska, MAC, gateway, DNS)"
  kmd sima-pc ip -br link; kmd sima-pc ip addr show eth0; kmd sima-pc ip route; kmd sima-pc cat /etc/resolv.conf; pauza
  korak "3. ping vlastite adrese, gatewaya, udaljenog hosta i imena: svaki korak provjerava jedan dio puta"
  ping1 sima-pc 192.168.20.50 "(vlastiti mrežni adapter)"
  ping1 sima-pc 192.168.20.1 "(gateway: izlaz iz LAN-a)"
  ping1 sima-pc 198.51.100.10 "(udaljeni host po IP adresi)"
  ping1 sima-pc klix.ba "(po imenu: provjerava i DNS)"; pauza
  korak "4. Izlaz pinga: RTT (vrijeme odziva), TTL (preostali broj skokova) i procenat izgubljenih paketa"
  kmd sima-pc ping -c4 klix.ba
  info "TTL u odgovoru je 63: server je poslao 64, a jedan ruter ga je smanjio za 1."
  kmd sima-pc ping -c1 -t1 198.51.100.10
  info "-t 1: paket smije preći samo jedan skok, pa ruter vraća 'Time to live exceeded' (na tome radi traceroute)."; pauza
  korak "5. traceroute (Windows: tracert): putanja paketa do odredišta, skok po skok"
  kmd sima-pc traceroute -n klix.ba; pauza
  korak "6. ss (Windows/stari Linux: netstat -an): konekcije i portovi; stanja LISTEN, ESTAB, TIME-WAIT"
  ip netns exec sima-pc bash -c 'exec 3<>/dev/tcp/198.51.100.10/80; sleep 15' & sleep 1
  kmd sima-pc curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://klix.ba/
  kmd sima-inet ss -tan
  info "LISTEN: server čeka konekcije (web 80, DNS 53; DNS upiti idu najčešće preko UDP-a: ss -uan).  ESTAB: uspostavljena konekcija."
  info "TIME-WAIT: konekcija je zatvorena, strana koja je prva zatvorila još čeka zakašnjele pakete."
  kmd sima-pc ss -tan
  kmd sima-inet ss -tlnp
  info "-t TCP, -u UDP, -a sve, -l samo LISTEN, -n bez prevođenja u imena (brže), -p proces koji drži port."
  echo; echo "Sada vježba s kvarom: make v2-p1-kvar, pa dijagnoza (ručno ili make v2-p1-dijagnoza), pa make v2-p1-rjesenje."
}

kvar() {
  treba_root kvar; lab_gore; ispravno
  local n="${1:-}" skriven=0
  if [ -z "$n" ]; then n=$((RANDOM % 6 + 1)); skriven=1; fi
  case "$n" in
    1) ip -n sima-ruter link set lan down ;;
    2) ip -n sima-pc route replace default via 192.168.20.254 ;;
    3) echo "nameserver 198.51.100.99" > /etc/netns/sima-pc/resolv.conf ;;
    4) ip -n sima-pc addr flush dev eth0; ip -n sima-pc addr add 192.168.21.50/24 dev eth0 ;;
    5) kill "$(cat "$LAB/web.pid")" 2>/dev/null; sleep 1 ;;
    6) ip netns exec sima-ruter sysctl -qw net.ipv4.ip_forward=0 ;;
    *) echo "Kvar je broj od 1 do 6"; exit 1 ;;
  esac
  echo "$n" > "$LAB/kvar"
  if [ "$skriven" = 1 ]; then echo "Ubačen je slučajan kvar. Korisnik javlja: 'nemam interneta, klix.ba ne radi'."
  else echo "Ubačen kvar $n: ${KVAROVI[$n]}"; fi
  echo "Ručna dijagnostika: sudo ip netns exec sima-pc bash   (pa ping, ip addr, ip route, dig, curl ...)"
  echo "Automatska: make v2-p1-dijagnoza"
}

dijagnoza() {
  treba_root dijagnoza
  ip netns list | grep -qw sima-pc || { echo "Lab ne postoji: make v2-p1-kvar"; exit 1; }
  local P="ip netns exec sima-pc"
  provjeri() { local opis="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$opis"; return 0; else ne "$opis"; return 1; fi; }
  korak "Dijagnostika odozdo prema gore (fizički sloj -> aplikacija); staje na prvom neuspjelom koraku"
  provjeri "1. link na eth0 (LOWER_UP: kabl je spojen)" sh -c "$P ip link show eth0 | grep -q LOWER_UP" \
    || { info "Uzrok: fizički sloj (kabl, utičnica, port na sviču, mrežna kartica). Provjeriti: ip -br link (NO-CARRIER)."; return; }
  provjeri "2. loopback i vlastita adresa (ping 127.0.0.1 i ping vlastite IP)" sh -c "$P ping -c1 -W1 127.0.0.1 && $P ip -4 -br addr show eth0 | grep -q '[0-9]/'" \
    || { info "Uzrok: TCP/IP stek ili sučelje nema adresu."; return; }
  provjeri "3. gateway iz tabele usmjeravanja odgovara" sh -c "$P ping -c1 -W1 \$($P ip route show default | awk '{print \$3}')" \
    || { $P ip -br -4 addr show eth0; $P ip route
         info "Uzrok: pogrešna adresa/maska (nije u podmreži gatewaya) ili pogrešan gateway. Uporediti adresu, masku i 'default via' s IP planom."; return; }
  provjeri "4. udaljeni host po IP adresi (198.51.100.10)" $P ping -c1 -W1 198.51.100.10 \
    || { info "Uzrok: iza gatewaya (ruter ne prosljeđuje, nema rute, ISP). traceroute -n 198.51.100.10 pokazuje gdje put staje:"; $P traceroute -n -q1 -w1 -m4 198.51.100.10; return; }
  provjeri "5. DNS: klix.ba se prevodi u adresu" sh -c "$P dig +short +time=1 +tries=1 klix.ba | grep -qE '^[0-9.]+$'" \
    || { $P cat /etc/resolv.conf; info "Uzrok: DNS (pogrešan ili nedostupan DNS server). IP promet radi, imena ne."; return; }
  provjeri "6. servis: web stranica odgovara (curl http://klix.ba)" $P curl -s -m2 -o /dev/null http://klix.ba/ \
    || { info "Uzrok: aplikacija/servis na serveru (mreža je ispravna). Na serveru: ss -tlnp (da li iko sluša na portu 80?)"; return; }
  echo; ok "Sve provjere su prošle: mreža i servis rade."
}

rjesenje() {
  treba_root rjesenje
  if [ -f "$LAB/kvar" ]; then n="$(cat "$LAB/kvar")"; echo "Kvar je bio $n: ${KVAROVI[$n]}"; else echo "Nema ubačenog kvara."; fi
  ip netns list | grep -qw sima-pc && ispravno && ok "vraćeno ispravno stanje"
}

dolje() { ns_obrisi $SVI; rm -rf "$LAB" /etc/netns/sima-pc; }

case "${1:-}" in
  vjezba) vjezba ;; kvar) kvar "${2:-}" ;; dijagnoza) dijagnoza ;; rjesenje) rjesenje ;; down) dolje ;;
  *) echo "Upotreba: $0 vjezba | kvar [1-6] | dijagnoza | rjesenje | down"; exit 1 ;;
esac
