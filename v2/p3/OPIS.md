# v2-p3: održavanje štampača (CUPS)

## Postavka

Na Linuxu štampom upravlja CUPS (Common UNIX Printing System): svaki štampač je red čekanja s adresom uređaja
(device URI). Mrežni štampač je emulator (`emulator_stampaca.py`) koji sluša na TCP portu 9100 (RAW/JetDirect, kao
većina mrežnih štampača) i svaki primljeni posao zapiše kao datoteku u `/var/tmp/sima-v2p3/izlaz/`.

## Problem

Najčešći softverski zastoji štampe sa slajdova: štampač nedostupan na mreži, poslovi koji se gomilaju u redu, zaglavljen
red koji treba očistiti. Administrator treba znati instalirati mrežni štampač, pratiti red čekanja i otkloniti zastoj
bez restartovanja svega.

## Pristup rješavanju

1. CUPS mora raditi (`lpstat -r`; ako ne radi, pokreće se servis).
2. "Uključen" mrežni štampač sluša na portu 9100 (`ss -tlnp`).
3. Instaliranje: `lpadmin -p sima-stampac -E -v socket://127.0.0.1:9100`, s lokacijom i opisom.
4. Štampa: `lp`, posao prolazi kroz red i završava kod štampača (`lpstat -W completed`).
5. Zastoj: štampač se gasi, novi posao ostaje u redu, a `lpstat -l` pokazuje poruku "unavailable".
6. Otklanjanje: štampač se pali, CUPS sam ponovo šalje posao i red se prazni.
7. Zaglavljen red: `cupsdisable` (pauza), tri posla u redu, `cancel` jednog, `cancel -a` za sve, `cupsenable`.
8. Dijeljenje štampača u mreži: naredbe za server i klijente se samo prikazuju.

## Arhitektonske odluke

- **Emulator na portu 9100 umjesto pravog štampača ili PDF štampača:** daje ono najvažnije za održavanje, a to je da se
  "uređaj" može ugasiti i upaliti, pa se vidi kako se CUPS ponaša kad je štampač nedostupan. Virtuelni PDF štampač
  nikad nije nedostupan.
- **Emulator radi na 127.0.0.1**, ne u namespace-u: CUPS je servis računara, pa bi štampač u namespace-u tražio mrežnu
  vezu između računara i laba (promjenu mreže računara).
- **RAW red (bez drajvera):** ne treba PPD ni filteri, a sadržaj posla stiže nepromijenjen pa se može pročitati.

## Dizajnerske odluke

- Koraci prate podjelu sa slajda na softverske zastoje: drajver/red, Ethernet sučelje (dostupnost uređaja), pa
  održavanje reda.
- Dijeljenje se samo prikazuje, jer `cupsctl --share-printers` mijenja postavke CUPS-a računara za cijelu mrežu.
- Poslovi imaju naslove (izvjestaj, faktura, ugovor...) da se u `lpstat` vidi koji je posao koji.

## Implementacijske odluke

- Upozorenje CUPS-a "Raw queues are deprecated" je očekivano i objašnjeno u ispisu; za pravi štampač se koristi
  `-m everywhere` (IPP Everywhere, bez drajvera proizvođača).
- Emulator imenuje poslove po broju postojećih datoteka (`posao-001.txt`...), pa ponovno pokretanje ne prepisuje
  ranije odštampane poslove.
- `cekaj_red` čeka da se red isprazni (do 40 s nakon paljenja štampača), jer CUPS socket backend ponovo pokušava slanje
  u intervalima.
- Ako `systemd` ne radi, `cupsd` se pokreće direktno (provjereno u okruženju bez systemd-a).
- `down` briše red i gasi emulator; CUPS servis ostaje kakav je bio.

## Pokretanje

```bash
make v2-p3          # lpstat -t (samo čita)
make v2-p3-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v2-p3-clean
```
