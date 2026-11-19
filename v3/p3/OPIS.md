# v3-p3: održavanje tvrdog diska (čišćenje, defragmentacija, TRIM)

## Postavka

`pregled` radi na disku računara (samo čita). Vježba koristi privremeni direktorij `/var/tmp/sima-temp` i disk od
128 MB s ext4 (datoteka `/var/tmp/sima-v3p3-disk.img` na loop uređaju, montirana na `/mnt/sima-hdd`). Konfiguracija
čišćenja je u `sima-ciscenje.conf` (format tmpfiles.d).

## Problem

Disk se puni (keš, dnevnici, privremene datoteke) i, kod HDD-a, fragmentira, pa računar usporava. Na Windowsu to
rješavaju Storage Sense i "Defragment and Optimize Drives". Treba pokazati: šta zauzima prostor, kako se čišćenje
automatizuje, šta je fragmentacija i zašto se SSD ne defragmentira.

## Pristup rješavanju

`pregled`: `df` (zauzeće), najveći direktoriji u home-u (`du`), tipični "potrošači" (keš paketa, journald dnevnici,
`~/.cache`, kanta za smeće, `/var/tmp`) i naredbe za njihovo čišćenje.

`vjezba`:
1. **Storage Sense:** tri datoteke starije od 7 dana i jedna nova; `systemd-tmpfiles --clean` s pravilom
   `d /var/tmp/sima-temp ... m:7d` briše samo stare. Na pravom sistemu pravilo ide u `/etc/tmpfiles.d/` i izvršava se
   dnevno (`systemd-tmpfiles-clean.timer`).
2. **Fragmentacija:** dvije datoteke se pišu naizmjenično u 64 komada od 64 KB uz `sync` nakon svakog; `filefrag`
   pokazuje 64 extenta po datoteci, `e4defrag -c` ocjenu fragmentacije.
3. **Defragmentacija:** `e4defrag` jedne datoteke, `filefrag` poslije: 1 extent (druga datoteka ostaje za poređenje).
4. **SSD:** ne defragmentira se; `fstrim` javlja disku koji su blokovi slobodni (Ubuntu to radi sedmično,
   `fstrim.timer`).

## Arhitektonske odluke

- **systemd-tmpfiles kao "Storage Sense":** to je mehanizam koji Linux već koristi za `/tmp` i `/var/tmp`, pa vježba
  uči alat iz prakse, a ne posebnu skriptu za brisanje.
- **Fragmentacija na posebnom malom disku:** na disku računara rezultat bi zavisio od svega što je već upisano i ne bi
  se mogao ponoviti; na praznom ext4 od 128 MB rezultat je uvijek isti (64 extenta).
- `pregled` čišćenje samo predlaže (ispis naredbi), jer `apt clean`, `journalctl --vacuum` i brisanje keša brišu
  stvarne podatke računara.

## Dizajnerske odluke

- Ostavljena je i jedna nova datoteka u čišćenju, da se vidi da pravilo briše po starosti, a ne sve.
- Defragmentira se samo jedna od dvije datoteke, pa su "prije" i "poslije" u istom ispisu.
- Uz rezultat se objašnjava da ext4 pri normalnom radu malo fragmentira (odgođena alokacija), pa ručna defragmentacija
  na Linuxu rijetko treba; fragmentacija u vježbi je namjerno izazvana.
- Napomena o SSD-u je poseban korak jer je "defragmentiraj sve" čest i pogrešan savjet.

## Implementacijske odluke

- `touch -d "N days ago"` mijenja samo vrijeme izmjene (mtime); vrijeme promjene inode-a (ctime) se ne može postaviti
  unazad. Zato pravilo koristi `m:7d` (starost samo po mtime-u). Za systemd stariji od 250 (bez te mogućnosti) skripta
  koristi `find -mtime +7 -delete` i to ispisuje.
- Fragmentacija se izaziva sa `dd oflag=append conv=notrunc` i `sync` nakon svakog komada: `sync` tjera ext4 da
  odmah dodijeli blokove, pa se komadi dvije datoteke smjenjuju na disku. Bez `sync`-a odgođena alokacija bi ih
  spojila.
- `fstrim` radi i na loop uređaju (prosljeđuje discard datoteci na disku računara).

## Pokretanje

```bash
make v3-p3          # zauzeće i prijedlozi čišćenja (samo čita)
make v3-p3-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v3-p3-clean
```
