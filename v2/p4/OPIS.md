# v2-p4: softverski RAID 1 (ogledalo)

## Postavka

Tri diska od 256 MB su datoteke u `/var/tmp/sima-v2p4` prikačene kao loop uređaji: disk1 i disk2 čine RAID 1, a
disk3 je rezervni za zamjenu. Polje se montira na `/mnt/sima-raid`. Alat je `mdadm` (Linux software RAID, ekvivalent
"New Mirrored Volume" u Windows Disk Managementu); ako jezgra nema md modul, koristi se btrfs RAID 1 s istim koracima.

## Problem

Disk je komponenta koja najčešće otkazuje i nosi podatke. Treba pokazati da RAID 1 omogućava rad i bez jednog diska,
kako se pokvaren disk mijenja bez gubitka podataka, i šta RAID **ne** rješava.

## Pristup rješavanju

1. Kreiranje ogledala (`mdadm --create --level=1` ili `mkfs.btrfs -d raid1 -m raid1`); kapacitet = manji disk.
2. Upis 40 MB podataka i jednog dokumenta, sa sha256 kontrolnim zbirom.
3. Kvar diska 2 (`mdadm --fail`, odnosno "vađenje" diska): polje radi u degradiranom stanju (`[U_]`),
   kontrolni zbir je ispravan, a u polje se može i pisati.
4. Zamjena: uklanjanje pokvarenog i dodavanje novog diska; obnova (resync/rebuild) kopira podatke na novi disk;
   kontrolni zbir ponovo ispravan.
5. "RAID nije backup": obrisana datoteka nestaje s oba diska.
6. (mdadm) trajna konfiguracija: `mdadm --detail --scan` za `/etc/mdadm/mdadm.conf` i nadzor `mdadm --monitor`.

## Arhitektonske odluke

- **Loop uređaji umjesto pravih diskova:** jezgra ih vidi kao blok uređaje isto kao SATA diskove, pa se mdadm/btrfs
  ponašaju isto, a diskovi računara su potpuno sigurni.
- **Dvije implementacije istih koraka (mdadm i btrfs):** WSL2 jezgra često nema md modul, a btrfs ima. Umjesto da
  vježba ne radi kod dijela studenata, skripta bira alat koji radi (`RAID_ALAT=btrfs` ga bira ručno).
- **Rezervni disk se pravi na početku** (disk3), jer se u praksi zamjenski disk drži spreman (hot spare).

## Dizajnerske odluke

- Ispravnost podataka se dokazuje kontrolnim zbirom (sha256) nakon svakog koraka, ne samo listanjem datoteka.
- Za vrijeme kvara se piše nova datoteka: pokazuje da sistem nastavlja raditi, a kod btrfs-a i zašto je poslije
  zamjene potreban `balance` (blokovi upisani bez kopije).
- Kod btrfs-a se prvo pokuša obično montiranje bez diska (odbija), pa `-o degraded`: zaštita od nesvjesnog rada bez kopije.
- Zadnji korak je namjerno "RAID nije backup", jer je to najčešća zabluda.

## Implementacijske odluke

- Izbor alata: mdadm samo ako `/proc/mdstat` postoji ili se `raid1` modul može učitati; inače btrfs.
- `mdadm --run` preskače interaktivno pitanje, a `mdadm --wait` čeka kraj sinhronizacije prije sljedećeg koraka.
- Kvar kod btrfs-a je stvarno otkačivanje loop uređaja (disk "izvađen"), a zamjena `btrfs replace start -B` po devid-u
  nestalog diska.
- `down`: umount, `mdadm --stop`, `--zero-superblock` na članovima, otkačivanje loop uređaja i
  `btrfs device scan --forget`, pa ponovno pokretanje uvijek kreće od nule.

Napomena: varijanta s btrfs-om je provjerena u razvojnom okruženju, a varijanta s mdadm-om nije (jezgra bez md modula).

## Pokretanje

```bash
make v2-p4                         # postojeći RAID nizovi (samo čita)
make v2-p4-lab                     # vježba (sudo), PAUZA=1 čeka Enter
sudo RAID_ALAT=btrfs bash v2/p4/raid1.sh vjezba
make v2-p4-clean
```
