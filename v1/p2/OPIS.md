# v1-p2: logičko segmentiranje IPv4 LAN mreže i IP plan

## Postavka

Zadatak s vježbi: mrežu 192.168.0.0/24 podijeliti na dvije podmreže, segment_1 do 100 računara i segment_2 do 50
računara. Skripta `ip_plan.py` prima mrežu i proizvoljan broj segmenata `ime:broj_racunara`, pa radi i za vlastite
zadatke (`make v1-p2 MREZA=10.10.0.0/23 SEG="uprava:120 proizvodnja:200 gosti:60"`).

## Problem

Za svaki segment treba odrediti dužinu maske, adresu podmreže, opseg hostova i broadcast, tako da se podmreže ne
preklapaju i stanu u zadatu mrežu. Iz toga treba napraviti **IP plan** (tabelu uređaja s adresama), koji je obavezan dio
projekta mreže.

## Pristup rješavanju

1. Za segment s `n` računara traži se najmanji broj bita za hostove `h` za koji je `2^h - 2 >= n`
   (mrežna i broadcast adresa se ne dodjeljuju). Za 100 računara: `2^7 = 128`, upotrebljivo 126.
2. Dužina maske je `32 - h` (ovdje /25 = 255.255.255.128), ispisana i binarno, kao na slajdu.
3. Segmenti se slažu od najvećeg prema najmanjem; svaka podmreža počinje na prvoj slobodnoj adresi djeljivoj veličinom
   bloka `2^h` (poravnanje), pa se blokovi ne preklapaju.
4. Dva načina:
   - **jednake podmreže** (kao na vježbama): maska se računa za najveći segment i koristi za sve (2 x /25);
   - **VLSM** (`--vlsm`): svaki segment dobija samo onoliko koliko treba (/25 + /26), pa ostaje 64 adrese za rast.
5. IP plan: prva adresa svake podmreže je gateway, zatim statičke adrese za server, mrežni štampač i upravljivi svič,
   ostatak je DHCP opseg. `--md datoteka` zapisuje plan kao Markdown tabelu za projekat.

## Arhitektonske odluke

- **Čist Python bez vanjskih paketa** (`ipaddress`, `math`, `argparse`): radi svugdje gdje je python3, bez root-a i bez
  mreže, pa je pogodan i za kućni rad i za ispit.
- **Jedan program za račun i za IP plan:** plan se izvodi iz istih podmreža, pa ne može doći do razilaženja između
  proračuna i dokumentacije projekta.

## Dizajnerske odluke

- Podrazumijevani način je "jednake podmreže" jer tako glasi rješenje na slajdu; VLSM je dodat kao proširenje i Makefile
  ispisuje oba, da se vidi cijena jednostavnosti (0 vs 64 slobodne adrese).
- Ispis prati korake rješenja s vježbi (broj bita, maska binarno, adresa podmreže binarno, opseg), pa student može
  uporediti svoj ručni rad red po red.
- Ispisuje se "rezerva za rast" po segmentu: projektant odmah vidi koliko mreža može narasti.
- Raspored statičkih adresa (gateway .1, zatim server, štampač, svič) slijedi uobičajenu praksu da su infrastrukturni
  uređaji na početku opsega, a klijenti u DHCP opsegu.

## Implementacijske odluke

- Poravnanje: `pocetak = ceil(slobodna / blok) * blok` u cjelobrojnoj aritmetici (`-(-a // b) * b`), bez petlji.
- Najmanji blok je /30 (`max(2, ...)`), jer manja podmreža nema upotrebljivih adresa za hostove.
- Ako segmenti ne stanu, program staje s jasnom porukom umjesto da napravi podmrežu izvan zadate mreže
  (`subnet_of` provjera).
- VLAN brojevi u IP planu (10, 20, ...) se slažu s `v1-p4`, gdje se isti segmenti prave kao VLAN-ovi.

## Pokretanje

```bash
make v1-p2
make v1-p2 MREZA=10.10.0.0/23 SEG="uprava:120 proizvodnja:200 gosti:60"
python3 v1/p2/ip_plan.py 192.168.0.0/24 segment_1:100 segment_2:50 --vlsm --md ip-plan.md
```
