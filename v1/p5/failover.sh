#!/usr/bin/env bash
# v1/p5/failover.sh: nadzor glavnog WAN linka i preključivanje na rezervni ("WAN failover" na Dual WAN ruteru).
# Pokreće se na ruteru (u labu: ip netns exec sima-ruter bash failover.sh).
#
# Svake sekunde šalje ping prema provjerenoj adresi KROZ glavni link (-I wan1, bez obzira na trenutnu rutu).
# Nakon PRAG uzastopnih neuspjeha prebacuje zadanu rutu na rezervni link; kad glavni opet odgovara PRAG puta zaredom,
# vraća promet na glavni.
set -u
CILJ="${CILJ:-198.51.100.10}"                      # u praksi: pouzdana javna adresa (npr. DNS server ISP-a)
GLAVNI_IF=wan1; GLAVNI_GW=100.64.1.1
REZERVNI_IF=wan2; REZERVNI_GW=100.64.2.1
PRAG="${PRAG:-3}"
INTERVAL="${INTERVAL:-1}"

aktivni=glavni; neuspjeh=0; uspjeh=0
log() { echo "$(date +%T) $*"; }
log "nadzor: ping $CILJ kroz $GLAVNI_IF svakih ${INTERVAL}s, prag $PRAG"

# ruta za provjeru: ping -I wan1 uvijek ide kroz glavni link, čak i kad je zadana ruta na rezervnom
ip route replace "$CILJ/32" via "$GLAVNI_GW" dev "$GLAVNI_IF" table 100
ip rule add from 100.64.1.2 lookup 100 priority 100 2>/dev/null || true

while true; do
  if ping -c1 -W1 -I 100.64.1.2 "$CILJ" >/dev/null 2>&1; then neuspjeh=0; uspjeh=$((uspjeh + 1))
  else uspjeh=0; neuspjeh=$((neuspjeh + 1)); fi

  if [ "$aktivni" = glavni ] && [ "$neuspjeh" -ge "$PRAG" ]; then
    ip route replace default via "$REZERVNI_GW" dev "$REZERVNI_IF" metric 50
    aktivni=rezervni; log "glavni link ne odgovara ($neuspjeh puta): promet ide preko $REZERVNI_IF (rezervni)"
  elif [ "$aktivni" = rezervni ] && [ "$uspjeh" -ge "$PRAG" ]; then
    ip route del default via "$REZERVNI_GW" dev "$REZERVNI_IF" metric 50
    aktivni=glavni; log "glavni link opet radi ($uspjeh puta): promet ide preko $GLAVNI_IF (glavni)"
  fi
  sleep "$INTERVAL"
done
