# v3-p1: ažuriranje operativnog sistema (ručno i automatizirano)

## Postavka

Ubuntu/Debian ažurira se preko `apt` iz repozitorija paketa. Automatske sigurnosne zakrpe radi paket
`unattended-upgrades`, a pokreću ga systemd timeri `apt-daily` i `apt-daily-upgrade`. U direktoriju su dvije
konfiguracijske datoteke: `20auto-upgrades` (šta se radi i koliko često) i `52sima-unattended-upgrades` (ponašanje
automatskog ažuriranja).

## Problem

Neažuriran sistem je najčešći put za malware i napade (slajd: "ažuriranje sistemskog i aplikativnog softvera").
Administrator treba znati: koja su ažuriranja dostupna i koja su sigurnosna, kako ih primijeniti bez iznenađenja, kako
ih automatizovati i kako provjeriti da automatika zaista radi (historija, potreban restart).

## Pristup rješavanju

`pregled` (samo čita):
1. verzija sistema i jezgre;
2. kada je zadnji put osvježen popis paketa (bez `apt update` sistem ne zna za nova ažuriranja);
3. broj dostupnih i broj sigurnosnih ažuriranja (iz simulacije `apt-get -s upgrade`);
4. da li je instaliran `unattended-upgrades`, njegove postavke (`apt-config dump`) i timeri;
5. da li je potreban restart (`/var/run/reboot-required`);
6. historija ažuriranja iz `/var/log/apt/history.log`.

`provjera`: `apt-config -c` čita obje datoteke iz repozitorija i javlja sintaksne greške bez ikakve primjene.

`apply` (opcionalno, root): `apt update`, simulacija ažuriranja, instalacija `unattended-upgrades`, kopiranje
konfiguracije u `/etc/apt/apt.conf.d/` i probni prolaz `unattended-upgrade --dry-run`.

## Arhitektonske odluke

- **Konfiguracija kao datoteke u repozitoriju** (a ne naredbe u skripti): ista datoteka se provjerava (`provjera`),
  primjenjuje (`apply`) i čita na nastavi, i može se kopirati na bilo koji računar.
- **Vlastita datoteka `52sima-...`** pored paketske `50unattended-upgrades`: postavke se dodaju bez mijenjanja datoteke
  paketa, pa nadogradnja paketa ne pravi sukob, a `down` uklanja samo našu datoteku.
- Simulacija (`-s`, `--dry-run`) umjesto stvarnog ažuriranja: vježba pokazuje šta bi se desilo, a stvarno ažuriranje
  student pokreće svjesno.

## Dizajnerske odluke

- `Automatic-Reboot` je `false` uz komentar da je na serveru `true` s terminom u 3 ujutro: studentov računar ne smije se
  sam restartovati zbog vježbe.
- `Remove-Unused-Kernel-Packages` i `Remove-Unused-Dependencies` su uključeni jer stare jezgre pune `/boot` (veza s
  održavanjem diska u `v3-p3`).
- Sigurnosna ažuriranja se broje posebno: prioritet održavanja nije "sve odmah", nego "sigurnosno odmah".

## Implementacijske odluke

- Vrijeme zadnjeg `apt update` se čita iz vremena izmjene najnovije `*Release` datoteke u `/var/lib/apt/lists`.
- Broj sigurnosnih ažuriranja se dobija iz linija `Inst` simulacije koje sadrže `security` (izvor paketa).
- Ispis probnog prolaza filtrira ključne linije (dozvoljeni izvori, paketi za nadogradnju) i **greške**, da se problem
  ne sakrije filtriranjem.
- Dijelovi koji traže systemd (timeri) se preskaču ako systemd ne radi (WSL bez `systemd=true`).

Napomena: probni prolaz `unattended-upgrade --dry-run` nije pokretan u razvojnom okruženju; `pregled` i `provjera` jesu.

## Pokretanje

```bash
make v3-p1          # pregled i provjera konfiguracije (samo čita)
make v3-p1-apply    # apt update, unattended-upgrades, probni prolaz (sudo)
make v3-p1-clean
```
