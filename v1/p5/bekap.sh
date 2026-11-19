#!/usr/bin/env bash
# v1/p5: bekap internet link za LAN mrežu (dual WAN ruter, failover). Ruter ima dva WAN sučelja prema dva
# različita ISP-a: glavni (optika) i rezervni (4G). Kad glavni link padne, promet prelazi na rezervni.
#
#   [pc] 192.168.10.50 --- lan [ruter] wan1 100.64.1.2 --- [isp1 optika] ---\
#                                       wan2 100.64.2.2 --- [isp2 4G]   -----[internet] 198.51.100.10
#
#   ./bekap.sh vjezba     cijela vježba (root)   PAUZA=1 čeka Enter
#   ./bekap.sh down       briše lab
#   failover.sh           nadzor glavnog linka (ping) i preključivanje rute, kao "WAN failover" na Dual WAN ruteru
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SVI="sima-pc sima-ruter sima-isp1 sima-isp2 sima-inet"
LAB=/run/sima-v1p5

put() { ip netns exec sima-pc traceroute -n -q1 -w1 -m5 198.51.100.10 2>/dev/null | awk 'NR>1 {printf "%s ", $2} END {print ""}'; }
ruta() { echo "   ruter: $(ip -n sima-ruter route show default | tr '\n' ';' | sed 's/;$//; s/;/  |  /g')"; }

izgradi() {
  for ns in $SVI; do ns_novi "$ns"; done
  veza sima-pc eth0 sima-ruter lan
  veza sima-ruter wan1 sima-isp1 kupac
  veza sima-ruter wan2 sima-isp2 kupac
  veza sima-isp1 gore sima-inet isp1
  veza sima-isp2 gore sima-inet isp2
  ip -n sima-pc addr add 192.168.10.50/24 dev eth0; ip -n sima-pc route add default via 192.168.10.1
  ip -n sima-ruter addr add 192.168.10.1/24 dev lan
  ip -n sima-ruter addr add 100.64.1.2/30 dev wan1; ip -n sima-ruter addr add 100.64.2.2/30 dev wan2
  ip netns exec sima-ruter sysctl -qw net.ipv4.ip_forward=1
  ip netns exec sima-ruter nft -f - <<'EOF'
table ip nat {
  chain post {
    type nat hook postrouting priority 100;
    oifname { "wan1", "wan2" } masquerade
  }
}
EOF
  local n
  for n in 1 2; do
    ip -n "sima-isp$n" addr add "100.64.$n.1/30" dev kupac
    ip -n "sima-isp$n" addr add "203.0.113.$((n * 4 - 3))/30" dev gore
    ip -n "sima-isp$n" route add default via "203.0.113.$((n * 4 - 2))"
    ip netns exec "sima-isp$n" sysctl -qw net.ipv4.ip_forward=1
    ip -n sima-inet addr add "203.0.113.$((n * 4 - 2))/30" dev "isp$n"
    ip -n sima-inet route add "100.64.$n.0/30" via "203.0.113.$((n * 4 - 3))"
  done
  ip -n sima-inet addr add 198.51.100.10/32 dev lo
}

vjezba() {
  treba_root vjezba; treba traceroute
  dolje >/dev/null 2>&1; mkdir -p "$LAB"
  izgradi

  korak "1. Dvije zadane rute: manja metrika ima prednost (glavni link), veća je rezerva"
  kmd sima-ruter ip route add default via 100.64.1.1 dev wan1 metric 100
  kmd sima-ruter ip route add default via 100.64.2.1 dev wan2 metric 200
  kmd sima-ruter ip route show default
  ping1 sima-pc 198.51.100.10 "(internet)"
  echo "   put paketa: $(put)"; pauza

  korak "2. Kvar A: kabl prema ISP1 izvučen (sučelje wan1 nema veze): jezgra sama koristi rezervnu rutu"
  kmd sima-ruter sysctl -w net.ipv4.conf.wan1.ignore_routes_with_linkdown=1
  kmd ip -n sima-isp1 link set kupac down
  sleep 1; kmd sima-ruter ip route show default
  ping1 sima-pc 198.51.100.10 "(internet)"
  echo "   put paketa: $(put)"
  kmd ip -n sima-isp1 link set kupac up
  sleep 1; echo "   put paketa nakon popravke: $(put)"; pauza

  korak "3. Kvar B: link radi, ali ISP1 nema internet (prekid kod ISP-a): ruta ostaje, promet se gubi"
  kmd ip -n sima-isp1 link set gore down
  kmd sima-ruter ip route show default
  ping1 sima-pc 198.51.100.10 "(internet)"
  info "Ruter 'ne zna' da je ISP1 bez interneta: zato Dual WAN ruteri stalno provjeravaju vezu (ping prema provjerenoj adresi)."; pauza

  korak "4. Failover: nadzor glavnog linka (failover.sh) prebacuje promet na rezervni link"
  ip netns exec sima-ruter bash "$DIR/failover.sh" > "$LAB/failover.log" 2>&1 &
  echo $! > "$LAB/failover.pid"
  sleep 6; kmd cat "$LAB/failover.log"
  ruta
  ping1 sima-pc 198.51.100.10 "(internet preko rezervnog linka)"
  echo "   put paketa: $(put)"; pauza

  korak "5. ISP1 ponovo radi: nadzor vraća promet na glavni (jeftiniji, brži) link"
  kmd ip -n sima-isp1 link set gore up
  kmd ip -n sima-isp1 route replace default via 203.0.113.2
  sleep 6; kmd cat "$LAB/failover.log"
  ruta
  echo "   put paketa: $(put)"
  kill "$(cat "$LAB/failover.pid")" 2>/dev/null
}

dolje() { [ -f "$LAB/failover.pid" ] && kill "$(cat "$LAB/failover.pid")" 2>/dev/null; ns_obrisi $SVI; rm -rf "$LAB"; }

case "${1:-}" in vjezba) vjezba ;; down) dolje ;; *) echo "Upotreba: $0 vjezba | down"; exit 1 ;; esac
