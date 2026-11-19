# v1-p5: bekap internet link za LAN mrežu (dual WAN, failover)

## Postavka

```
[pc] 192.168.10.50 --- lan [ruter] wan1 100.64.1.2 --- [isp1 optika] ---\
                                    wan2 100.64.2.2 --- [isp2 4G]   -----[internet] 198.51.100.10
```

Ruter ima dva WAN sučelja prema dva različita ISP-a (kao DrayTek Vigor2920 sa slajda) i NAT na oba. Internet ima
povratne rute prema adresama oba ISP-a.

## Problem

Kad glavni link padne, LAN mora nastaviti raditi preko rezervnog, i vratiti se na glavni kad on proradi. Postoje dvije
vrste kvara koje se ponašaju potpuno različito:
- **kvar A:** link prema ISP-u fizički padne (kabl, modem), pa ruter to "vidi";
- **kvar B:** link radi, ali ISP nema internet, pa ruter ništa ne primjećuje i promet tiho nestaje.

## Pristup rješavanju

1. Dvije zadane rute s različitom metrikom (100 glavni, 200 rezervni); traceroute pokazuje put preko ISP1.
2. Kvar A: gašenje porta na strani ISP1. Uz `ignore_routes_with_linkdown=1` jezgra ruti dodaje oznaku `linkdown` i
   automatski koristi rezervnu; nakon popravke se sama vraća.
3. Kvar B: ISP1 gubi vezu prema internetu; obje rute izgledaju ispravno, ping ne prolazi. Dokaz da je potreban nadzor.
4. `failover.sh` (kao "WAN failover" na Dual WAN ruteru): svake sekunde ping prema provjerenoj adresi **kroz glavni link**;
   nakon 3 uzastopna neuspjeha dodaje zadanu rutu preko rezervnog linka s metrikom 50 (ima prednost).
5. ISP1 proradi: nakon 3 uzastopna uspjeha nadzor briše rutu s metrikom 50 i promet se vraća na glavni link.

## Arhitektonske odluke

- **Pet namespace-ova** (pc, ruter, dva ISP-a, internet): svaki ISP ima svoj uplink, pa se kvar B može napraviti kod
  ISP-a, a ne na ruteru, baš kao u stvarnosti.
- **Failover rutiranjem, ne mijenjanjem NAT-a ili sučelja:** ruter samo bira zadanu rutu, a NAT (`masquerade` na oba
  WAN-a) automatski koristi adresu izlaznog sučelja.
- **Nadzor kao posebna skripta na ruteru** (`failover.sh`), koja se može čitati i pokrenuti samostalno: odgovara
  funkciji koju na komercijalnom ruteru podešavamo u web sučelju.
- Adrese: 100.64.0.0/10 (Carrier-grade NAT, kakve ISP-ovi zaista daju), 203.0.113.0/24 i 198.51.100.0/24
  (dokumentacijski opsezi), pa se lab nikad ne sudara sa stvarnim mrežama.

## Dizajnerske odluke

- Kvar A i kvar B su odvojeni koraci jer je razlika između njih glavna pouka: metrika rješava samo kvar koji ruter vidi.
- **Histereza** (3 neuspjeha za prelazak, 3 uspjeha za povratak): jedan izgubljen paket ne smije prebacivati promet
  amo-tamo ("flapping").
- Rezervna ruta se dodaje s **manjom** metrikom (50) umjesto brisanja glavne: povratak je samo brisanje dodane rute, a
  originalna konfiguracija rutera se nikad ne mijenja.
- Prikaz puta (`traceroute`) u jednom redu (`192.168.10.1 100.64.2.1 198.51.100.10`) da se preko kojeg ISP-a ide vidi
  na prvi pogled.

## Implementacijske odluke

- Nadzor mora provjeravati glavni link **i dok promet ide preko rezervnog**. Zato ping ide s izvornom adresom
  `100.64.1.2`, a pravilo `ip rule from 100.64.1.2 lookup 100` šalje takve pakete kroz tabelu 100, koja ima rutu samo
  preko wan1 (policy routing).
- `ip link set ... down` briše rute s tog sučelja, pa se pri popravci kod ISP-a zadana ruta ISP-a vraća eksplicitno
  (`ip route replace`), kao što bi to uradio ISP.
- Prag i interval su varijable okruženja (`PRAG`, `INTERVAL`, `CILJ`) da se ponašanje može mijenjati bez izmjene koda.
- Nadzor se pokreće u pozadini, PID se čuva u `/run/sima-v1p5`, a `down` ga gasi prije brisanja namespace-ova.

## Pokretanje

```bash
make v1-p5          # shema laba
make v1-p5-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v1-p5-clean
```
