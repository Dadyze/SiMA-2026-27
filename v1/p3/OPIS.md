# v1-p3: kaskadna (hijerarhijska) Ethernet LAN mreža

## Postavka

Četiri sviča u tri nivoa, četiri računara i server, svi u jednoj podmreži 192.168.1.0/24:

```
nivo 1 (jezgro)          [core] ------------------ srv 192.168.1.10
                         /      \
nivo 2 (pristup)     [sw1]      [sw2] ----------- pc21 .121
                     /   \          \
                 pc11    pc12      [sw3]          nivo 3 (kaskada)
                 .111    .112          \
                                       pc31 .131
```

## Problem

Na slajdu je kaskadna mreža s napomenom "ne preporučuje se više od 3 nivoa". Studenti trebaju vidjeti **zašto**: kako
svič uči gdje je koji računar, kuda prolazi promet iz dubine kaskade i šta se desi kad otkaže jedan uplink.

## Pristup rješavanju

1. Izgradnja: svaki svič je Linux bridge u svom namespace-u, uplinkovi su veth parovi između bridge-eva.
2. Provjera povezanosti: svi računari vide server; pc11 vidi pc31 preko sva tri nivoa (jedan broadcast domen).
3. MAC tabele (`bridge fdb`): jezgro sve računare iza sw2 i sw3 vidi **na istom portu** (sw2), a sw2 vidi sve izvan
   sebe na uplinku. To je "učenje" sviča.
4. Promet kroz nivoe: 20 pingova pc31 -> server i brojači paketa na uplinkovima pokazuju da promet prolazi kroz sw3 i
   sw2, a uplink sw1 ostaje na nuli. Uplink višeg nivoa nosi zbir prometa svega ispod njega (usko grlo).
5. Kvar: prekid uplinka sw2 -> core odsijeca i pc21 i cijeli sw3; pc11 i pc12 rade. Zaključak: jedna tačka otkaza na
   višem nivou ruši cijeli dio kaskade, pa se nivoi ograničavaju, a uplinkovi prave brži i redundantni (STP).

## Arhitektonske odluke

- **Linux bridge kao svič:** bridge radi isto što i neupravljivi svič (uči MAC adrese, prosljeđuje okvire, poplavljuje
  nepoznate), a `bridge fdb` daje pravu MAC tabelu za prikaz.
- **Svaki svič u svom namespace-u:** imena portova (`uplink`, `pc21`, `sw3`) su lokalna za svič, kao na pravom uređaju,
  i kvar se simulira gašenjem jednog porta na jednom sviču.
- **Jedna podmreža bez rutera:** tema je sloj 2 (kaskada svičeva), pa ruter namjerno nije dio laba.

## Dizajnerske odluke

- Tri nivoa (a ne dva kao na slajdu) da se vidi i "dubina" kaskade iz napomene o najviše 3 nivoa.
- Kvar se pravi na uplinku nivoa 2 jer je to najpoučniji slučaj: pogađa i direktno spojen računar i cijeli niži nivo.
- MAC tabela se prikazuje po imenima računara (ne kao sirova lista adresa), da je čitljiva na projektoru.
- `DRY=1` (osnovni cilj `make v1-p3`) ispisuje sve naredbe bez izvršavanja, kao `s4-p2` u RuO.

## Implementacijske odluke

- Topologija je zadana podacima (`SVICEVI`, parovi uplinkova `core:sw1 core:sw2 sw2:sw3`, `HOSTOVI` kao
  `ns:adresa:svič`), a izgradnja je jedna petlja po vrsti elementa: dodavanje nivoa ili računara je jedan red.
- Brojači prometa se čitaju iz `ip -s -j link` (JSON) prije i poslije pingova i oduzimaju, pa ne smeta pozadinski
  promet (ARP i sl.).
- Nakon izgradnje se čeka 1 s da bridge portovi pređu u stanje forwarding prije ispisa stanja.
- Čišćenje briše sve namespace-ove (s njima nestaju i veth parovi i bridge-evi), pa nema ostataka na računaru.

## Pokretanje

```bash
make v1-p3          # ispis naredbi (DRY=1)
make v1-p3-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v1-p3-clean
```
