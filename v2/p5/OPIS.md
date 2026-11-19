# v2-p5: particije diska (MBR i GPT), UUID, fstab i boot opcije

## Postavka

Prazan disk od 1 GB je datoteka `/var/tmp/sima-v2p5-disk.img` prikačena kao loop uređaj s particijama (`losetup -P`).
Na njemu se pravi prvo MBR, a zatim GPT raspored kakav ima UEFI računar.

## Problem

Instalacija i održavanje klijentskog računara traže razumijevanje tabele particija (MBR ili GPT), posebnih particija
(EFI/System Reserved, recovery), datotečnih sistema i toga kako sistem zna šta montirati pri pokretanju. Greška u bilo
čemu od toga znači računar koji se ne podiže.

## Pristup rješavanju

1. `pregled` (stvarni računar): tabele particija (`PTTYPE` dos/gpt), UEFI ili BIOS, boot opcije jezgre
   (`/proc/cmdline`), `/etc/fstab`.
2. MBR: tri primarne particije (prva označena kao bootable/aktivna), proširena i dvije logičke unutar nje, jedna swap.
   Pokazuje ograničenje na 4 primarne particije.
3. GPT: EFI System Partition 100 MB, sistem, podaci i recovery particija, s imenima particija.
4. Datotečni sistemi: FAT32 za EFI (to traži UEFI), ext4 za ostale, s oznakama (label).
5. UUID i PARTUUID (`blkid`) i iz njih generisane linije za `/etc/fstab`; montiranje particije s podacima.
6. Bootabilni USB: naredbe za pronalaženje USB-a i `dd`, samo prikaz.

## Arhitektonske odluke

- **Disk-datoteka s particijama na loop uređaju:** ista alatka (`sfdisk`, `fdisk`, `mkfs`, `blkid`) i isti rezultat kao
  na pravom disku, bez rizika za diskove računara.
- **Raspored particija kao deklarativna skripta za `sfdisk`** (vidljiva prije primjene): isti raspored se može ponoviti
  na stotinu računara, što je i način rada pri masovnoj instalaciji.
- GPT raspored odgovara slajdovima o System Reserved i Recovery particiji, preveden na UEFI/Linux: ESP je mjesto boot
  loadera i za Windows i za Linux.

## Dizajnerske odluke

- Prvo MBR pa GPT na **istom** disku (`wipefs` između), da se razlike vide na istom ispisu `fdisk -l`.
- fstab linije se generišu iz stvarnih UUID-ova i objašnjava se zašto UUID, a ne `/dev/sdX` (ime uređaja se može
  promijeniti kad se doda disk).
- Bootabilni USB se **ne** izvršava: `dd` na pogrešan uređaj briše disk, pa se uz naredbu ističe razlika `sdX`/`sdX1`.
- Preporuka "sistem na SSD-u, podaci posebno" sa slajda je uz korak s particijom za podatke.

## Implementacijske odluke

- Nakon `sfdisk` se poziva `partx -u` (i `udevadm settle` ako postoji), jer bez udev-a (kontejneri, dio WSL okruženja)
  jezgra ne napravi odmah `/dev/loopNpM` čvorove.
- Tipovi particija su sfdisk skraćenice (`U` = EFI System, `L` = Linux filesystem; za MBR `83`, `82`, `5`), čitljivije
  od punih GUID-ova.
- Prikaz u koraku 4 koristi `lsblk`, a koraci koji moraju raditi i bez udev-a (UUID, fstab) koriste `blkid`, koji čita
  disk direktno.

## Pokretanje

```bash
make v2-p5          # diskovi, UEFI/BIOS, fstab ovog računara (samo čita)
make v2-p5-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v2-p5-clean
```
