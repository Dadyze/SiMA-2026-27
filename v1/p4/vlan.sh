#!/usr/bin/env bash
# v1/p4: VLAN-ovi na upravljivom sviču i pristup internetu iz VLAN podmreža preko zajedničkog rutera.
# Segmenti su iz v1/p2 (192.168.0.0/24 podijeljena na dvije /25). Svič je Linux bridge s VLAN filtriranjem,
# ruter ima po jedno VLAN podsučelje za svaki segment ("router on a stick") i NAT prema internetu.
#
#            VLAN 10 (uprava) 192.168.0.0/25          VLAN 20 (gosti) 192.168.0.128/25
#            pc1 .10    pc2 .11                       pc3 .130    pc4 .131
#              p1 |       | p2                          p3 |        | p4      access portovi (untagged)
#             [================== svič (bridge, VLAN filtering) ==================]
#                                     | p5  trunk (tagged 10 i 20)
#                                  [ruter]  eth0.10 192.168.0.1, eth0.20 192.168.0.129
#                                     | wan 203.0.113.2/30 (NAT)
#                                  [internet]  198.51.100.10
#
#   ./vlan.sh vjezba       cijela vježba korak po korak (root)    PAUZA=1 čeka Enter
#   ./vlan.sh status       VLAN tabela sviča i adrese
#   ./vlan.sh down         briše lab
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
SVI="sima-pc1 sima-pc2 sima-pc3 sima-pc4 sima-svic sima-ruter sima-inet"
PC="sima-pc1:10:192.168.0.10/25:192.168.0.1 sima-pc2:10:192.168.0.11/25:192.168.0.1 sima-pc3:20:192.168.0.130/25:192.168.0.129 sima-pc4:20:192.168.0.131/25:192.168.0.129"
SW() { kmd ip netns exec sima-svic "$@"; }

izgradi() {
  modprobe 8021q 2>/dev/null || true
  ns_novi sima-svic
  if ! ip -n sima-svic link add br0 type bridge vlan_filtering 1 2>/dev/null; then
    echo "Jezgra ne podržava VLAN filtriranje na bridge-u (CONFIG_BRIDGE_VLAN_FILTERING)."; dolje >/dev/null; exit 1
  fi
  ip -n sima-svic link set br0 up
  local i=1 h ns
  for h in $PC; do
    ns="${h%%:*}"; ns_novi "$ns"
    ip link add "p$i" netns sima-svic type veth peer name eth0 netns "$ns"
    ip -n sima-svic link set "p$i" master br0 up; ip -n "$ns" link set eth0 up
    i=$((i + 1))
  done
  ns_novi sima-ruter; ns_novi sima-inet
  ip link add p5 netns sima-svic type veth peer name eth0 netns sima-ruter
  ip -n sima-svic link set p5 master br0 up; ip -n sima-ruter link set eth0 up
  veza sima-ruter wan sima-inet eth0
  ip -n sima-ruter addr add 203.0.113.2/30 dev wan; ip -n sima-ruter route add default via 203.0.113.1
  ip -n sima-inet addr add 203.0.113.1/30 dev eth0; ip -n sima-inet addr add 198.51.100.10/32 dev lo
}

stanje() {
  korak "VLAN tabela sviča (bridge vlan show): PVID = VLAN untagged okvira, Egress Untagged = skida oznaku"
  SW bridge vlan show
  for ns in sima-ruter sima-pc1 sima-pc3; do kmd "$ns" ip -br -4 addr; done
}

vjezba() {
  treba_root vjezba
  dolje >/dev/null 2>&1
  izgradi

  korak "1. Svič bez VLAN-ova: svi portovi su u VLAN 1 (jedan broadcast domen)"
  for h in $PC; do IFS=: read -r ns vlan ip gw <<<"$h"; kmd "$ns" ip addr add "$ip" dev eth0; done
  SW bridge vlan show
  ping1 sima-pc1 192.168.0.11 "(pc1 -> pc2, segment 1)"
  info "Gost (pc3) sam sebi postavi adresu iz segmenta uprave i odmah je 'unutra':"
  kmd sima-pc3 ip addr add 192.168.0.12/25 dev eth0
  ping1 sima-pc3 192.168.0.10 "(gost pc3 -> pc1 uprave)"
  kmd sima-pc3 ip addr del 192.168.0.12/25 dev eth0
  info "Podjela adresa (v1/p2) je samo logička; bez VLAN-a svič ne razdvaja segmente."; pauza

  korak "2. Kreiranje VLAN-ova i access portova (web sučelje sviča: VLAN -> Create, Modify Port -> Access -> Untagged)"
  info "Access port: okviri ulaze bez oznake, svič ih stavlja u VLAN (pvid) i skida oznaku na izlazu (untagged)."
  for h in $PC; do
    IFS=: read -r ns vlan ip gw <<<"$h"; port="p${ns#sima-pc}"
    SW bridge vlan del dev "$port" vid 1
    SW bridge vlan add dev "$port" vid "$vlan" pvid untagged
  done
  korak "3. Trunk port prema ruteru (p5): nosi oba VLAN-a, okviri imaju 802.1Q oznaku (tagged)"
  SW bridge vlan del dev p5 vid 1
  SW bridge vlan add dev p5 vid 10
  SW bridge vlan add dev p5 vid 20
  SW bridge vlan show; pauza

  korak "4. Izolacija: unutar VLAN-a radi, između VLAN-ova ne (ni kad gost prepiše tuđu adresu)"
  ping1 sima-pc1 192.168.0.11 "(VLAN 10: pc1 -> pc2)"
  ping1 sima-pc3 192.168.0.131 "(VLAN 20: pc3 -> pc4)"
  kmd sima-pc3 ip addr add 192.168.0.12/25 dev eth0
  ping1 sima-pc3 192.168.0.10 "(gost s adresom uprave -> pc1: svič ne pušta okvir u VLAN 10)"
  kmd sima-pc3 ip addr del 192.168.0.12/25 dev eth0
  ping1 sima-pc1 192.168.0.130 "(VLAN 10 -> VLAN 20: nema rutera)"; pauza

  korak "5. Ruter: VLAN podsučelja na trunku su gatewayi segmenata (router on a stick)"
  kmd sima-ruter ip link add link eth0 name eth0.10 type vlan id 10
  kmd sima-ruter ip link add link eth0 name eth0.20 type vlan id 20
  kmd sima-ruter ip addr add 192.168.0.1/25 dev eth0.10
  kmd sima-ruter ip addr add 192.168.0.129/25 dev eth0.20
  kmd sima-ruter ip link set eth0.10 up
  kmd sima-ruter ip link set eth0.20 up
  kmd sima-ruter sysctl -w net.ipv4.ip_forward=1
  for h in $PC; do IFS=: read -r ns vlan ip gw <<<"$h"; kmd "$ns" ip route add default via "$gw"; done
  ping1 sima-pc1 192.168.0.130 "(VLAN 10 -> VLAN 20 preko rutera)"
  kmd sima-pc1 traceroute -n -q1 -w1 192.168.0.130; pauza

  korak "6. Pristup internetu: bez NAT-a internet ne zna put nazad do privatnih adresa 192.168.0.0/24"
  ping1 sima-pc1 198.51.100.10 "(internet, bez NAT-a)"
  kmd sima-ruter nft add table ip nat
  kmd sima-ruter nft add chain ip nat post '{ type nat hook postrouting priority 100 ; }'
  kmd sima-ruter nft add rule ip nat post oifname wan masquerade
  ping1 sima-pc1 198.51.100.10 "(VLAN 10 -> internet, NAT)"
  ping1 sima-pc3 198.51.100.10 "(VLAN 20 -> internet, NAT)"; pauza

  korak "7. Izolovana mreža za goste: VLAN 20 ima internet, ali ne smije u VLAN 10"
  kmd sima-ruter nft add table inet filter
  kmd sima-ruter nft add chain inet filter fwd '{ type filter hook forward priority 0 ; }'
  kmd sima-ruter nft add rule inet filter fwd ct state established,related accept
  kmd sima-ruter nft add rule inet filter fwd iifname eth0.20 oifname eth0.10 drop
  ping1 sima-pc3 192.168.0.10 "(gost -> uprava)"
  ping1 sima-pc3 198.51.100.10 "(gost -> internet)"
  ping1 sima-pc1 192.168.0.130 "(uprava -> gost: dozvoljeno, odgovor prolazi kao established)"
  kmd sima-ruter nft list ruleset
}

dolje() { ns_obrisi $SVI; }

case "${1:-}" in vjezba) vjezba ;; status) stanje ;; down) dolje ;; *) echo "Upotreba: $0 vjezba | status | down"; exit 1 ;; esac
