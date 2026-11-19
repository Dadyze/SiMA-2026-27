#!/usr/bin/env bash
# v1/p1: konfigurisanje mrežnog sučelja na Linuxu: pregled (ekvivalent ipconfig /all), statička adresa,
# gateway i DNS, pa DHCP. Vježba se radi u dva izolirana namespace-a, pa mreža računara ostaje netaknuta:
#
#   [sima-pc] eth0 ---- kabl (veth) ---- eth0 [sima-rtr]  192.168.1.1/24, DHCP + DNS server (dnsmasq)
#
#   ./konfiguracija.sh pregled     samo čita mrežne postavke ovog računara (ne traži root)
#   ./konfiguracija.sh vjezba      statička adresa, gateway, DNS, pa DHCP (root)   PAUZA=1 čeka Enter
#   ./konfiguracija.sh provjera    provjera netplan primjera (netplan generate u privremenom direktoriju)
#   ./konfiguracija.sh down        briše namespace-ove
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
LAB=/run/sima-v1p1

# DHCP klijent u namespace-u: bez skripti (ne dira ime ni DNS računara) i sa zakupima u privremenom direktoriju,
# da ništa ne ostane u /var/lib/dhcpcd računara
dhcp_klijent() {
  echo "[pc]\$ dhcpcd $*"; mkdir -p /var/lib/dhcpcd
  ip netns exec sima-pc unshare -m sh -c 'mount -t tmpfs none /var/lib/dhcpcd && exec dhcpcd -c /bin/true "$@"' dhcpcd "$@"
  return 0
}

pregled() {
  korak "1. Sučelja (ip -br link): ime, stanje (UP/DOWN), MAC adresa"
  kmd ip -br link
  korak "2. IP adrese (ip -br addr): Linux ekvivalent za ipconfig"
  kmd ip -br addr
  korak "3. Detalji sučelja (ip addr show): prefiks, broadcast, dynamic = adresa iz DHCP-a (valid_lft = trajanje zakupa)"
  kmd ip addr show
  korak "4. Tabela usmjeravanja: 'default via' je gateway (izlaz iz LAN-a)"
  kmd ip route
  kmd ip route get 1.1.1.1
  korak "5. DNS serveri"
  if command -v resolvectl >/dev/null && resolvectl status >/dev/null 2>&1; then kmd resolvectl dns; else kmd cat /etc/resolv.conf; fi
  korak "6. ARP tabela (ip neigh): IP -> MAC adrese uređaja s kojima je računar nedavno komunicirao"
  kmd ip neigh
  korak "7. Trajna konfiguracija: netplan (Ubuntu) u /etc/netplan/"
  kmd ls -l /etc/netplan/ 2>/dev/null
  info "Naredbe 'ip ...' mijenjaju stanje samo do restarta; trajno se konfiguriše u /etc/netplan/*.yaml (vidi netplan-*.yaml)."
}

vjezba() {
  treba_root vjezba; treba dnsmasq; treba dhcpcd; treba dig
  down >/dev/null 2>&1
  mkdir -p "$LAB" /etc/netns/sima-pc
  ns_novi sima-pc; ns_novi sima-rtr
  ip link add eth0 netns sima-pc type veth peer name eth0 netns sima-rtr
  ip -n sima-rtr addr add 192.168.1.1/24 dev eth0; ip -n sima-rtr link set eth0 up
  ip -n sima-rtr addr add 198.51.100.10/32 dev lo        # "server na internetu" iza rutera
  ip netns exec sima-rtr sysctl -qw net.ipv4.ip_forward=1
  # DNS + DHCP server na ruteru; zakup 24h (tipična postavka na kućnim i uredskim ruterima)
  ip netns exec sima-rtr dnsmasq --conf-file=/dev/null --pid-file="$LAB/dnsmasq.pid" --interface=eth0 --bind-interfaces \
    --no-resolv --no-hosts --address=/server.lan/192.168.1.10 --address=/klix.ba/198.51.100.10 \
    --dhcp-range=192.168.1.100,192.168.1.199,255.255.255.0,24h --dhcp-option=option:router,192.168.1.1 \
    --dhcp-option=option:dns-server,192.168.1.1 --dhcp-leasefile="$LAB/dnsmasq.leases" --log-facility="$LAB/dnsmasq.log"

  korak "1. Novo sučelje: postoji, ali je isključeno (DOWN) i nema IP adresu"
  kmd sima-pc ip -br link show eth0; kmd sima-pc ip -br addr show eth0; pauza

  korak "2. Statička adresa: uključiti sučelje i dodati adresu u obliku adresa/prefiks (/24 = 255.255.255.0)"
  kmd sima-pc ip link set eth0 up
  kmd sima-pc ip addr add 192.168.1.50/24 dev eth0
  kmd sima-pc ip -br addr show eth0
  kmd sima-pc ip route
  info "Jezgra je sama dodala rutu za lokalnu podmrežu (192.168.1.0/24 dev eth0): ovi hostovi su 'na istom kablu'."
  ping1 sima-pc 192.168.1.1 "(gateway, ista podmreža)"
  ping1 sima-pc 198.51.100.10 "(server izvan LAN-a)"; pauza

  korak "3. Gateway (zadani put): sve što nije u lokalnoj podmreži šalje se ruteru"
  kmd sima-pc ip route add default via 192.168.1.1
  kmd sima-pc ip route
  ping1 sima-pc 198.51.100.10 "(server izvan LAN-a)"; pauza

  korak "4. DNS: imena se pretvaraju u adrese tek kad je zadan DNS server"
  echo "# prazno: DNS server nije zadan" > /etc/netns/sima-pc/resolv.conf
  kmd sima-pc dig +short +time=1 +tries=1 klix.ba
  echo "nameserver 192.168.1.1" > /etc/netns/sima-pc/resolv.conf; echo "\$ echo 'nameserver 192.168.1.1' > /etc/resolv.conf"
  kmd sima-pc dig +short klix.ba
  kmd sima-pc ping -c1 -W1 klix.ba
  info "Bez DNS-a mreža radi (ping na IP prolazi), ali korisnik 'nema interneta' jer imena ne rade."; pauza

  korak "5. DHCP: brišemo statičku konfiguraciju i tražimo adresu od DHCP servera (DISCOVER, OFFER, REQUEST, ACK)"
  kmd sima-pc ip addr flush dev eth0
  kmd sima-pc ip -br addr show eth0
  dhcp_klijent -4 -1 -B -q -t 15 eth0
  kmd sima-pc ip addr show eth0
  kmd sima-pc ip route
  info "Adresa je 'dynamic', a valid_lft je preostalo trajanje zakupa (lease, ovdje 24h = 86400 s)."
  korak "6. Zakupi na DHCP serveru: vrijeme isteka, MAC, IP i ime klijenta"
  kmd cat "$LAB/dnsmasq.leases"
  kmd grep -E 'DHCP(DISCOVER|OFFER|REQUEST|ACK)' "$LAB/dnsmasq.log"
  ping1 sima-pc 198.51.100.10 "(preko gatewaya iz DHCP-a)"; pauza

  korak "7. Mreža bez DHCP servera: klijent dobija samo link-local adresu 169.254.x.x (APIPA); statičke adrese i dalje rade"
  kill "$(cat "$LAB/dnsmasq.pid")" 2>/dev/null; sleep 1
  kmd sima-pc ip addr flush dev eth0
  dhcp_klijent -4 -1 -B -q -t 5 eth0
  kmd sima-pc ip -br addr show eth0
  info "169.254.0.0/16 znači: 'DHCP server nije odgovorio'. S takvom adresom nema gatewaya ni interneta."
  kmd sima-pc ip addr flush dev eth0
  kmd sima-pc ip addr add 192.168.1.50/24 dev eth0
  ping1 sima-pc 192.168.1.1 "(statička adresa radi i bez DHCP servera)"
  echo
  echo "Promjene su privremene (nestaju s namespace-om, a na pravoj mašini s restartom)."
  echo "Trajna konfiguracija na Ubuntuu: netplan (v1/p1/netplan-staticki.yaml i netplan-dhcp.yaml)."
}

provjera() {
  korak "netplan: statička i DHCP konfiguracija (provjera bez primjene: netplan generate u privremenom direktoriju)"
  for f in netplan-staticki.yaml netplan-dhcp.yaml; do
    echo "--- $f"; cat "$DIR/$f"
    if command -v netplan >/dev/null; then
      T="$(mktemp -d)"; mkdir -p "$T/etc/netplan"; install -m 600 "$DIR/$f" "$T/etc/netplan/$f"
      if netplan generate --root-dir "$T" 2>&1; then ok "$f je ispravan"; else ne "$f ima grešku"; fi
      rm -rf "$T"
    else
      python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$DIR/$f" && ok "$f: YAML ispravan (netplan nije instaliran)"
    fi
  done
  info "Primjena na pravoj mašini: sudo cp ... /etc/netplan/ && sudo netplan try (vraća staro ako se potvrda ne da za 120 s)"
}

down() { ns_obrisi sima-pc sima-rtr; rm -rf "$LAB" /etc/netns/sima-pc; }

case "${1:-}" in pregled) pregled ;; vjezba) vjezba ;; provjera) provjera ;; down) down ;;
  *) echo "Upotreba: $0 pregled | vjezba | provjera | down"; exit 1 ;; esac
