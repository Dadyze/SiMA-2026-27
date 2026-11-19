# v3-p2: zaštita od štetnog softvera (ClamAV)

## Postavka

Linux ekvivalent Microsoft Defendera je ClamAV: `clamscan` (skener), `freshclam` (ažuriranje baze potpisa),
`clamonacc` (skeniranje u realnom vremenu). U direktoriju `/var/tmp/sima-v3p2-<korisnik>` se prave "dokumenti",
EICAR test datoteka (standardna bezopasna datoteka koju svaki antivirus prijavljuje kao virus) i izmišljeni "uzorak"
`faktura.pdf.exe`.

## Problem

Treba razumjeti kako antivirus prepoznaje štetni softver (potpisi), zašto se baza potpisa mora stalno ažurirati, šta
se radi s pronađenom datotekom (karantena) i kako se zaštita automatizuje, bez korištenja pravog malwarea.

## Pristup rješavanju

1. Verzija ClamAV-a i stanje službene baze.
2. Datoteke za skeniranje: dva dokumenta, EICAR, "zaražena faktura".
3. **Vlastita baza potpisa**, dvije vrste:
   - hash potpis (`.hdb`): MD5 i veličina cijele datoteke (`sigtool --md5`);
   - sadržajni potpis (`.ndb`): niz bajtova koji se traži bilo gdje u datoteci.
4. Skeniranje (`clamscan -r -i`): pronađene su EICAR i faktura; izlazni kod 1 znači "pronađeno".
5. Promjena jednog bajta u uzorku: hash potpis ga više ne prepoznaje, sadržajni i dalje. Zato se baza ažurira više puta
   dnevno i zato antivirusi kombinuju vrste potpisa.
6. Karantena: `--move` premješta zaražene datoteke na izolovano mjesto; dokumenti ostaju.
7. Automatizacija (prikaz): servis `clamav-freshclam`, zakazano skeniranje (cron), `clamonacc`.

`apply` (opcionalno): preuzima službenu bazu (`freshclam`, ~200 MB) i skenira EICAR njome, bez naših potpisa.

## Arhitektonske odluke

- **Vlastita baza potpisa umjesto službene** u osnovnoj vježbi: radi bez interneta i bez preuzimanja ~200 MB, a
  student vidi da je "potpis" obična linija teksta koju može sam napisati. Službena baza je opcionalan dodatak.
- **EICAR + izmišljeni uzorak, bez pravog malwarea:** sigurno za računare studenata i za repozitorij.
- Vježba radi **bez root-a**, u direktoriju po korisniku: skeniranje i karantena ne traže privilegije, pa ih ne treba
  ni davati.

## Dizajnerske odluke

- Korak s promjenom jednog bajta skenira posebno samo `.hdb`, pa samo `.ndb` bazom: razlika je u dva susjedna reda
  ispisa ("OK" i "FOUND").
- Uzorak se zove `faktura.pdf.exe` jer je dvostruka ekstenzija u prilogu e-pošte stvaran i čest trik.
- Karantena je zadnji korak u vježbi da se prije toga vidi šta je pronađeno, kao u Defenderu (detekcija, pa akcija).

## Implementacijske odluke

- EICAR string nije u repozitoriju u jednom komadu; sastavlja se pri pokretanju iz dva dijela, pa ni GitHub ni
  antivirus na računaru studenta ne prijavljuju repozitorij.
- Sadržajni potpis se pravi iz oznake uzorka pretvorene u heksadecimalni zapis (`od -An -tx1`), format
  `ime:0:*:hex` (tip 0 = bilo koja datoteka, `*` = bilo koja pozicija).
- Direktorij vježbe ima ime korisnika (`sima-v3p2-$(id -un)`), pa raniji `sudo` prolaz ne ostavlja datoteke koje
  običan korisnik ne može obrisati.
- `apply` zaustavlja `clamav-freshclam` servis dok radi ručni `freshclam` (inače je baza zaključana) i ponovo ga pokreće.

## Pokretanje

```bash
make v3-p2          # vježba (bez sudo), PAUZA=1 čeka Enter
make v3-p2-apply    # službena baza i skeniranje njome (sudo, internet)
make v3-p2-clean
```
