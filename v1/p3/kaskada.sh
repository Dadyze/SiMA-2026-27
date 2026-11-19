#!/usr/bin/env bash
# v1/p3: kaskadna (hijerarhijska) Ethernet LAN mreža. Svičevi su Linux bridge-evi, svaki u svom namespace-u,
# a računari su namespace-ovi spojeni "kablom" (veth). Sve je jedna podmreža 192.168.1.0/24 (jedan broadcast domen).
#
#   nivo 1 (jezgro)          [core] ------------------ srv 192.168.1.10
#                            /      \
#   nivo 2 (pristup)     [sw1]      [sw2] ----------- pc21 .121
#                        /   \          \
#                    pc11    pc12      [sw3]          nivo 3 (kaskada)
#                    .111    .112          \
#                                          pc31 .131
#
#   ./kaskada.sh up | status | down       DRY=1 ./kaskada.sh up   samo ispisuje naredbe
#   ./kaskada.sh vjezba                   up + provjere, MAC tabele, promet kroz nivoe i kvar uplinka (root)
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/../../lib/zajednicko.sh"
DRY="${DRY:-0}"
SVICEVI="sima-core sima-sw1 sima-sw2 sima-sw3"
HOSTOVI="sima-srv:10:core sima-pc11:111:sw1 sima-pc12:112:sw1 sima-pc21:121:sw2 sima-pc31:131:sw3"
SVI="$SVICEVI $(for h in $HOSTOVI; do printf '%s ' "${h%%:*}"; done)"

run() { echo "+ $*"; [ "$DRY" = 1 ] || "$@"; }

gore() {
  if [ "$DRY" != 1 ]; then treba_root up; ip netns list | grep -qw sima-core && { echo "lab već postoji (./kaskada.sh down)"; return 0; }; fi
  echo "# 1. svičevi: namespace + bridge br0 (bridge uči MAC adrese i prosljeđuje okvire kao svič)"
  for s in $SVICEVI; do
    run ip netns add "$s"; run ip -n "$s" link add br0 type bridge; run ip -n "$s" link set br0 up
  done
  echo "# 2. uplinkovi između svičeva (kaskada): core<-sw1, core<-sw2, sw2<-sw3"
  for par in core:sw1 core:sw2 sw2:sw3; do
    gornji="sima-${par%%:*}"; donji="sima-${par##*:}"
    run ip link add "${par##*:}" netns "$gornji" type veth peer name uplink netns "$donji"
    run ip -n "$gornji" link set "${par##*:}" master br0 up
    run ip -n "$donji" link set uplink master br0 up
  done
  echo "# 3. računari i server: kabl do sviča, adresa iz 192.168.1.0/24"
  for h in $HOSTOVI; do
    IFS=: read -r ns ip sw <<<"$h"
    run ip netns add "$ns"; run ip -n "$ns" link set lo up
    run ip link add "${ns#sima-}" netns "sima-$sw" type veth peer name eth0 netns "$ns"
    run ip -n "sima-$sw" link set "${ns#sima-}" master br0 up
    run ip -n "$ns" addr add "192.168.1.$ip/24" dev eth0
    run ip -n "$ns" link set eth0 up
  done
}

stanje() {
  for s in $SVICEVI; do
    printf '%-5s portovi: ' "${s#sima-}"
    bridge -n "$s" -j link show | python3 -c "import json,sys; print('  '.join(f\"{p['ifname']} ({p.get('state','?')})\" for p in json.load(sys.stdin)))"
  done
}

# mac_tabela svic: naučene MAC adrese računara i port na kojem ih svič vidi
mac_tabela() {
  local h mac port
  for h in $HOSTOVI; do
    h="${h%%:*}"; mac="$(ip -n "$h" -br link show eth0 | awk '{print $3}')"
    port="$(ip netns exec "$1" bridge fdb show br br0 | awk -v m="$mac" '$1==m {print $3; exit}')"
    printf '   %-5s %s  ->  port %s\n' "${h#sima-}" "$mac" "${port:-(još nije naučena)}"
  done
}

# promet ns: broj paketa poslanih kroz uplinkove (tx), da se vidi kojim svičevima prolazi saobraćaj
brojaci() { for u in sima-sw1:uplink sima-sw2:uplink sima-sw3:uplink; do ip -n "${u%%:*}" -s -j link show "${u##*:}" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['stats64']['rx']['packets'])"; done; }

vjezba() {
  treba_root vjezba
  dolje >/dev/null 2>&1
  korak "1. Izgradnja mreže: 4 sviča u 3 nivoa, 4 računara i server"
  DRY=0 gore | grep '^#'
  sleep 1; stanje; pauza

  korak "2. Svi računari vide server (jedna podmreža, jedan broadcast domen)"
  for h in sima-pc11 sima-pc12 sima-pc21 sima-pc31; do ping1 "$h" 192.168.1.10 "(server)"; done
  ping1 sima-pc11 192.168.1.131 "(pc11 -> pc31, preko sva tri nivoa)"; pauza

  korak "3. MAC tabele: svaki svič uči na kojem portu je koja MAC adresa (bridge fdb)"
  for s in sima-core sima-sw2; do echo "--- MAC tabela sviča ${s#sima-}"; mac_tabela "$s"; done
  info "Jezgro (core) vidi MAC adrese svih računara: one iza sw2 i sw3 vidi na istom portu (sw2)."; pauza

  korak "4. Saobraćaj kroz nivoe: 20 pingova pc31 -> server prolazi kroz sw3, sw2 i core"
  read -r a1 a2 a3 < <(brojaci | xargs)
  ip netns exec sima-pc31 ping -c20 -i0.01 -q 192.168.1.10 | tail -2
  read -r b1 b2 b3 < <(brojaci | xargs)
  printf '   paketi kroz uplink sw1: %d   sw2: %d   sw3: %d\n' $((b1-a1)) $((b2-a2)) $((b3-a3))
  info "Uplink sw2 nosi promet i od pc21 i od svih računara ispod sw3: viši nivoi su usko grlo."; pauza

  korak "5. Kvar: kabl između core i sw2 (uplink) je prekinut"
  kmd ip -n sima-sw2 link set uplink down
  for h in sima-pc11 sima-pc12 sima-pc21 sima-pc31; do ping1 "$h" 192.168.1.10 "(server)"; done
  info "Jedan prekinut uplink odsijeca cijeli dio kaskade ispod njega (sw2 i sw3): zato se ne preporučuje više od 3 nivoa,"
  info "a uplinkovi na višim nivoima trebaju biti brži i, gdje je moguće, redundantni (dva kabla + STP)."
  kmd ip -n sima-sw2 link set uplink up; sleep 1
  ping1 sima-pc31 192.168.1.10 "(nakon popravke)"
}

dolje() { ns_obrisi $SVI; }

case "${1:-}" in
  up) gore ;; status) stanje ;; vjezba) vjezba ;; down) dolje ;;
  *) echo "Upotreba: [DRY=1] $0 up | status | vjezba | down"; exit 1 ;;
esac
