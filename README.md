# Sistemska i mrežna administracija 2026/27: primjeri s vježbi (Linux)

Univerzitet u Zenici, Politehnički fakultet, Odsjek za softversko inženjerstvo.
Asistent: ass. Mr. Adin Jahić.

Repozitorij sadrži vježbe iz prezentacija V6, V7 i V8, urađene na **Linuxu**. Svaka vježba je prava skripta koja se
pokreće jednom naredbom `make`, pa se na nastavi odmah vidi šta se radi. Mreže se grade u Linux network namespace-ovima,
a diskovi su datoteke prikačene kao loop uređaji: mreža i diskovi računara ostaju netaknuti.

| Vježba | Prezentacija | Tema | Primjeri |
|---|---|---|---|
| 1 | V6 | Konfigurisanje mreže i mrežno okruženje | `v1/p1` mrežne postavke, statička adresa, gateway, DNS, DHCP, netplan; `v1/p2` logičko segmentiranje IPv4 i IP plan; `v1/p3` kaskadna hijerarhijska LAN; `v1/p4` VLAN, router on a stick, NAT, izolacija gostiju; `v1/p5` bekap internet link (dual WAN, failover); `v1/projekat` projekat LAN mreže |
| 2 | V7 | Održavanje mreže i računara | `v2/p1` dijagnostika (ping, ip, traceroute, ss) i traženje kvara; `v2/p2` pouzdanost složenih sistema; `v2/p3` štampači (CUPS); `v2/p4` softverski RAID 1; `v2/p5` particije MBR/GPT, UUID, boot; `v2/p6` virtuelna mašina (KVM) |
| 3 | V8 | Održavanje klijentskog OS-a | `v3/p1` ažuriranje (apt, unattended-upgrades); `v3/p2` zaštita od malwarea (ClamAV); `v3/p3` održavanje diska (čišćenje, defragmentacija, TRIM); `v3/p4` tačka vraćanja (btrfs snapshot); `v3/p5` nadzor performansi i programi pri pokretanju |

Windows alati s vježbi i njihovi Linux ekvivalenti:

| Windows | Linux | Primjer |
|---|---|---|
| `ipconfig /all` | `ip addr`, `ip route`, `resolvectl` | `v1-p1`, `v2-p1-lab` |
| `ping`, `tracert`, `netstat -an` | `ping`, `traceroute`, `ss -tan` | `v2-p1-lab` |
| web sučelje upravljivog sviča (VLAN) | `bridge vlan` | `v1-p4-lab` |
| Devices and Printers | CUPS (`lpadmin`, `lpstat`, `cancel`) | `v2-p3-lab` |
| Disk Management, New Mirrored Volume | `mdadm` / btrfs RAID 1 | `v2-p4-lab` |
| Disk Management (particije), System Reserved | `sfdisk`, `fdisk`, EFI particija, `blkid`, `/etc/fstab` | `v2-p5-lab` |
| Hyper-V Manager | KVM/libvirt (`virt-install`, `virsh`, `virt-manager`) | `v2-p6` |
| Windows Update | `apt`, `unattended-upgrades` | `v3-p1` |
| Microsoft Defender | ClamAV (`clamscan`, `freshclam`) | `v3-p2` |
| Storage Sense, Defragment and Optimize | `systemd-tmpfiles`, `e4defrag`, `fstrim` | `v3-p3-lab` |
| Restore Point, System Protection, Task Scheduler | btrfs snapshot (Timeshift, Snapper), systemd timer | `v3-p4-lab` |
| Task Manager, Startup | `top`, `ps`, `free`, `vmstat`, `iostat`, `kill`, `systemctl enable/disable` | `v3-p5` |

## Getting started: korak po korak

Ovo je cijeli put od praznog računara do prve pokrenute vježbe. Koraci 1 do 5 rade se **jednom**.

### 0. Šta mora postojati na Windowsu

| Šta | Zašto | Kako |
|---|---|---|
| **WSL2 s Ubuntu 22.04 ili 24.04** | sve vježbe rade na Linuxu | PowerShell: `wsl --install -d Ubuntu` |

Linux korisnici nemaju ovaj korak: dovoljno je Ubuntu/Debian s `apt`.

### 1. Otvorite Ubuntu i klonirajte repozitorij u home direktorij

```bash
cd ~ && git clone https://github.com/Dadyze/SiMA-2026-27.git && cd SiMA-2026-27
```

Repozitorij treba biti u Linux fajl sistemu (`~/...`), **ne** u `/mnt/c/...` (Windows disk).

### 2. Pokrenite instalacijsku skriptu

```bash
./00-setup.sh
```

Traži sudo lozinku i instalira sve potrebno (detalji u odjeljku "Instalacija" niže). Na kraju ispisuje listu alata
(svaki treba biti `ok`) i provjerava da li jezgra ima ono što labovi koriste (VLAN na bridge-u, md RAID, btrfs).

Ako ispiše `systemd nije uključen`: u **PowerShellu** pokrenite `wsl --shutdown`, ponovo otvorite Ubuntu i ponovo
`./00-setup.sh`. `systemd` treba za CUPS (`v2-p3`), servise (`v3-p5`) i libvirt (`v2-p6`).

### 3. Provjerite alate

```bash
make check
```

### 4. Pokrenite prvu vježbu

```bash
make v1-p1          # mrežne postavke ovog računara (samo čita)
make v1-p1-lab      # statička adresa, gateway, DNS, pa DHCP u izoliranom labu (sudo)
```

### 5. Ostale vježbe, redom

```bash
make help
```

`make help` ispisuje sve ciljeve po vježbama. `PAUZA=1` (npr. `make v1-p3-lab PAUZA=1`) čeka Enter nakon svakog koraka,
što je zgodno za rad na nastavi.

### 6. Čišćenje

```bash
make clean-all
```

## Šta je potrebno

Sve se pokreće u **Linux okruženju**: Ubuntu 22.04/24.04 ili **WSL2** na Windowsu.

| Alat | Potreban za | Napomena |
|---|---|---|
| `git`, `make`, `python3` | sve | |
| `iproute2` (`ip`, `bridge`, `ss`), `ping`, `traceroute`, `dig`, `nftables` | vježba 1, `v2/p1` | `-lab` ciljevi traže `sudo` (network namespace-ovi) |
| `dnsmasq`, `dhcpcd` | `v1/p1`, `v2/p1` | DNS i DHCP server/klijent u labu; ne dira mrežu računara |
| CUPS | `v2/p3` | štampač je emulator na portu 9100 |
| `mdadm`, `btrfs-progs`, `fdisk`, `dosfstools` | `v2/p4`, `v2/p5`, `v3/p3`, `v3/p4` | diskovi su datoteke u `/var/tmp` |
| KVM/libvirt, `virt-install` | `v2/p6` | samo za stvarno pokretanje VM-a; `make v2-p6` radi i bez njih |
| `unattended-upgrades`, ClamAV, `sysstat` | vježba 3 | |

### Instalacija: prva skripta `00-setup.sh`

Pokreće se kao običan korisnik, a `sudo` traži sama:

```bash
./00-setup.sh        # ili: make setup
```

Šta radi (idempotentno, može se pokrenuti više puta):

1. provjerava okruženje (Linux, apt, WSL2; ako treba, uključuje `systemd` u `/etc/wsl.conf`),
2. instalira `git`, `make`, `python3`,
3. instalira mrežne alate: `iproute2`, `ping`, `traceroute`, `dig`, `dnsmasq-base`, `dhcpcd`, `nftables`, `netplan`,
4. instalira CUPS i dodaje korisnika u grupu `lpadmin`,
5. instalira alate za diskove: `mdadm`, `btrfs-progs`, `fdisk`, `dosfstools`,
6. instalira `unattended-upgrades`, ClamAV i `sysstat`,
7. instalira KVM/libvirt i `virt-install` i pravi SSH ključ `~/.ssh/id_ed25519`,
8. ispisuje provjeru alata i mogućnosti jezgre.

Opcije: `SKIP_LIBVIRT=1` (bez KVM-a), `SKIP_CLAMAV=1` (bez ClamAV-a).

## Upotreba make-a

Svaki primjer ima oznaku `v<vježba>-p<primjer>`. Naredba `make v1-p1` pokreće primjer 1 iz vježbe 1 i ispisuje svaku
naredbu koja se izvršava. Isto radi i `make run EX=v1-p1`.

### Opis primjera: `-desc`

Svaki primjer ima cilj `-desc` koji ispisuje detaljan opis: **postavku** (topologija, diskovi, servisi), **problem** koji
se rješava, **pristup rješavanju** korak po korak te **arhitektonske, dizajnerske i implementacijske odluke** (zašto je
lab napravljen baš tako). Isti tekst je u datoteci `OPIS.md` u direktoriju primjera.

```bash
make v1-p4-desc      # ili: less v1/p4/OPIS.md
```

### Pravilo: osnovni cilj samo čita, `-lab` gradi lab

**Osnovni cilj svakog primjera ne mijenja sistem**: pregled stanja računara, shema laba, ispis naredbi ili provjera
konfiguracije. Ciljevi koji nešto prave imaju sufiks `-lab` (izolirani lab: namespace-ovi, loop diskovi, `sudo`),
`-apply` ili `-up` (mijenjaju računar: paketi, postavke, VM) i za svaki postoji `-clean`.

| Cilj | Šta radi | Mijenja sistem? |
|---|---|---|
| `make v1-p1` / `v1-p1-lab` | mrežne postavke računara (ipconfig /all) / statička adresa, gateway, DNS, DHCP (zakup 24h), mreža bez DHCP-a (169.254.x.x) | ne / lab |
| `make v1-p1-netplan` | provjera netplan primjera (statički i DHCP) naredbom `netplan generate` | ne |
| `make v1-p2` | segmentiranje 192.168.0.0/24 (100 + 50 računara), binarne maske, opsezi, IP plan; jednake podmreže i VLSM | ne |
| `make v1-p3` / `v1-p3-lab` | kaskadna LAN: ispis naredbi / 4 sviča u 3 nivoa, MAC tabele, promet kroz nivoe, kvar uplinka | ne / lab |
| `make v1-p4` / `v1-p4-lab` | VLAN: shema / VLAN 10 i 20, access i trunk portovi, router on a stick, NAT, izolacija gostiju | ne / lab |
| `make v1-p5` / `v1-p5-lab` | bekap link: shema / dva ISP-a, metrike, kvar kabla, kvar kod ISP-a, automatski failover i povratak | ne / lab |
| `make v2-p1` / `v2-p1-lab` | dijagnostika: Windows i Linux naredbe / ping, ip addr, TTL, traceroute, ss (LISTEN, ESTAB, TIME-WAIT) | ne / lab |
| `make v2-p1-kvar` / `-dijagnoza` / `-rjesenje` | ubaci kvar (`KVAR=1..6` ili slučajan), dijagnostika odozdo prema gore, rješenje | lab |
| `make v2-p2` | pouzdanost: RAID 1 (2 x 0.97 = 99.91 %), računar od komponenti 0.95, serijski/paralelno | ne |
| `make v2-p3` / `v2-p3-lab` | štampači: lpstat / mrežni štampač, štampa, štampač nedostupan, zaglavljen red, cancel | ne / CUPS red `sima-stampac` |
| `make v2-p4` / `v2-p4-lab` | RAID: pregled / RAID 1, kvar diska, degradirani rad, zamjena, obnova, "RAID nije backup" | ne / lab |
| `make v2-p5` / `v2-p5-lab` | particije: pregled, UEFI/BIOS / MBR (primarne, proširena, logičke), GPT (EFI, sistem, podaci, recovery), UUID, fstab | ne / lab |
| `make v2-p6` / `v2-p6-up` | VM: preduslovi i plan / Ubuntu VM (1 GB RAM, 10 GB disk, cloud-init) | ne / da (KVM) |
| `make v3-p1` / `v3-p1-apply` | ažuriranje: dostupna i sigurnosna ažuriranja, postavke, historija / apt update, unattended-upgrades | ne / da |
| `make v3-p2` / `v3-p2-apply` | ClamAV: vlastiti potpisi, EICAR, hash i sadržajni potpis, karantena / službena baza (freshclam) | datoteke u `/var/tmp` / da |
| `make v3-p3` / `v3-p3-lab` | disk: zauzeće i čišćenje / tmpfiles (Storage Sense), fragmentacija, e4defrag, fstrim | ne / lab |
| `make v3-p4` / `v3-p4-lab` | tačka vraćanja: provjera timera / snapshot, loša instalacija, vraćanje (podaci ostaju), retencija | ne / lab |
| `make v3-p5` / `v3-p5-lab` | nadzor: load, memorija, procesi, disk, servisi pri startu / zaglavljen proces, renice, kill, enable/disable servisa | ne / lab |
| `make vN-pM-desc` | opis primjera: postavka, problem, pristup, arhitektonske/dizajnerske/implementacijske odluke | ne |
| `make all` | svi osnovni ciljevi redom | ne |
| `make lab-all` | svi `-lab` ciljevi redom, svaki se odmah čisti | lab |
| `make clean-all` | čisti sve primjere | uklanja |

### Redoslijed

```bash
./00-setup.sh      # jednom
make check
make v1-p1         # mreža: postavke računara, pa v1-p1-lab
make v1-p2         # segmentiranje i IP plan
make v1-p3-lab     # kaskadna LAN
make v1-p4-lab     # VLAN
make v1-p5-lab     # bekap link
make v2-p1-lab     # dijagnostika, pa v2-p1-kvar / v2-p1-dijagnoza / v2-p1-rjesenje
make v2-p2         # pouzdanost
make v2-p3-lab     # štampači ... i dalje redom do v3-p5-lab
```

## Rješavanje problema

| Simptom | Rješenje |
|---|---|
| `Jezgra ne podržava VLAN filtriranje na bridge-u` (`v1-p4-lab`) | jezgra bez `CONFIG_BRIDGE_VLAN_FILTERING`/`8021q`; na WSL2: `wsl --update` (novija jezgra), ili Ubuntu u VM-u |
| `v2-p4-lab` piše "Alat: btrfs" | jezgra nema md RAID (česta u WSL2): koraci su isti, samo s btrfs RAID 1. `RAID_ALAT=btrfs` bira btrfs i kad md radi |
| `CUPS ne radi` (`v2-p3-lab`) | `sudo systemctl status cups`; u WSL2 mora biti uključen `systemd` |
| `systemd nije aktivan` (`v3-p5-lab`) | dio sa servisima se preskače; uključiti `systemd=true` u `/etc/wsl.conf`, pa `wsl --shutdown` |
| `libvirt ne radi` / nema `/dev/kvm` (`v2-p6`) | ostati na `make v2-p6` (plan); VM traži ugniježđenu virtualizaciju |
| lab je ostao napola (prekinut Ctrl+C) | `make v1-p3-clean` (ili odgovarajući `-clean`); svaki `-lab` prvo sam čisti prethodno stanje |
| `make: *** missing separator` | koristi se Makefile iz ovog repozitorija (prefiks naredbi je `>`, ne tabulator); GNU make 3.82+ |

## Struktura

```
Makefile        # make help
00-setup.sh     # instalacija alata
lib/            # zajedničke funkcije skripti (ispis naredbi, ping, namespace-ovi)
vN/pM/OPIS.md   # opis svakog primjera (make vN-pM-desc)
v1/p1..p5/      # vježba 1 (V6): mrežne postavke i DHCP, segmentiranje, kaskadna LAN, VLAN, bekap link
v1/projekat/    # projektni zadatak: idejni projekat LAN mreže
v2/p1..p6/      # vježba 2 (V7): dijagnostika, pouzdanost, štampači, RAID 1, particije, VM
v3/p1..p5/      # vježba 3 (V8): ažuriranje, antimalware, disk, tačka vraćanja, nadzor
```

Status provjere: svi osnovni ciljevi (`make all`) i `-lab` ciljevi `v1-p1`, `v1-p3`, `v1-p5`, `v2-p1` (sa svih 6 kvarova),
`v2-p3`, `v2-p4` (btrfs varijanta), `v2-p5`, `v3-p2`, `v3-p3`, `v3-p4` i `v3-p5` (bez dijela sa systemd servisom) izvršeni su
od početka do kraja u razvojnom okruženju (Ubuntu 24.04). Napisani prema dokumentaciji, ali nisu pokretani jer razvojna
jezgra nema potrebne module: `v1-p4-lab` (VLAN), `v2-p4-lab` s mdadm-om, `v2-p6-up` (KVM), dio `v3-p5-lab` sa systemd
servisom i `v3-p1-apply` (probni prolaz unattended-upgrades). Ako nešto ne radi, javiti asistentu.
