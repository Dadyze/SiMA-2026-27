# v3-p4: tačka vraćanja sistema (Restore Point) na Linuxu

## Postavka

Disk od 512 MB s btrfs-om (`/var/tmp/sima-v3p4-btrfs.img`, montiran na `/mnt/sima-btrfs`) ima dva subvolumena, kao
standardna btrfs instalacija Ubuntua:

```
@sistem        programi i postavke (na pravom računaru montiran kao /)
@home          podaci korisnika (na pravom računaru /home)
.snapshots/    tačke vraćanja: read-only snapshotovi @sistem
```

Pomoćne datoteke: `napravi-rp.sh` (pravi tačku vraćanja i briše stare), `sima-restore-point.service` i
`sima-restore-point.timer` (automatska tačka jednom dnevno).

## Problem

Instalacija programa ili promjena postavki pokvari sistem. Treba ga vratiti u prethodno ispravno stanje **bez gubitka
korisničkih podataka** nastalih u međuvremenu (Windows: "Restore Point vraća sistemske datoteke i aplikacije, podaci se
ne vraćaju"). Tačke vraćanja se trebaju praviti automatski, a stare brisati.

## Pristup rješavanju

1. Disk sa `@sistem` (program verzija 1.0, `port=80`) i `@home` (prvo poglavlje diplomskog).
2. Tačka vraćanja prije instalacije: read-only snapshot `@sistem`, trenutan i bez kopiranja podataka.
3. "Loša instalacija": program 2.0 koji ne radi i pokvarena konfiguracija; korisnik u međuvremenu piše drugo poglavlje.
4. Vraćanje: pokvaren `@sistem` se sklanja, iz tačke vraćanja se pravi novi (upisivi) `@sistem`, pokvaren se briše.
   Rezultat: program 1.0 i `port=80`, a **oba** poglavlja u `@home` su tu.
5. Automatske tačke vraćanja: timer `OnCalendar=daily` (Windows: 1440 minuta u RegEdit + Task Scheduler) i retencija:
   osam novih tačaka uz `ZADRZI=7` ostavlja sedam najnovijih (briše se i najstarija, ona iz koraka 2).

`provjera` validira timer i servis (`systemd-analyze verify`, `systemd-analyze calendar daily`) i sintaksu skripte,
bez instalacije.

## Arhitektonske odluke

- **btrfs snapshot kao tačka vraćanja:** copy-on-write snapshot je trenutan i zauzima prostor tek kad se sistem mijenja,
  pa se tačke mogu praviti često. Isti mehanizam koriste Timeshift (btrfs način) i Snapper.
- **Odvojeni subvolumeni za sistem i podatke:** granica između "šta se vraća" i "šta ostaje" je fizička (dva
  subvolumena), a ne lista izuzetaka. Tako je rasporedio i Ubuntu instalater (`@` i `@home`).
- **Tačke su read-only:** tačka vraćanja se ne može slučajno izmijeniti; za vraćanje se iz nje pravi nova upisiva kopija.
- **Automatika kao systemd timer + servis** (umjesto cron-a): `Persistent=true` pravi propuštenu tačku nakon
  pokretanja ugašenog računara, a `systemctl list-timers` pokazuje sljedeće izvršavanje.

## Dizajnerske odluke

- Korisnik piše novi dokument **između** tačke vraćanja i vraćanja: to je jedini način da se pokaže da se podaci ne
  vraćaju.
- Vraćanje radi "zamjenom subvolumena" (sklanjanje, snapshot iz tačke, brisanje pokvarenog), što je korak po korak ono
  što alati rade ispod haube; uz to se navodi da se na pravom računaru to radi iz Timeshifta/Snappera i završava restartom.
- Retencija je u istoj skripti koja pravi tačku, pa tačke ne mogu napuniti disk ni kad timer radi mjesecima.
- Opis tačke je dio imena (`RP-datum-vrijeme-prije-instalacije`), kao opis Restore Pointa u Windowsu.

## Implementacijske odluke

- Retencija sortira tačke po **ogen** (generacija btrfs-a u kojoj je snapshot nastao), ne po imenu: imena s istim
  vremenom (više tačaka u istoj sekundi) i različitim opisima se ne sortiraju po starosti.
- Ako tačka s istim imenom već postoji (ista sekunda), dodaje se redni broj.
- `systemd-analyze verify` se pokreće nad kopijom unit datoteka s putanjom do skripte u repozitoriju, jer servis
  pokazuje na `/usr/local/sbin/napravi-rp.sh` (mjesto instalacije na pravom sistemu).
- `ZADRZI` je varijabla okruženja, a u servisu `Environment=ZADRZI=7`.

## Pokretanje

```bash
make v3-p4          # provjera timera i skripte (ništa se ne instalira)
make v3-p4-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v3-p4-clean
```
