# v2-p6: instaliranje virtuelne mašine (KVM/libvirt, Linux ekvivalent Hyper-V Managera)

## Postavka

Hipervizor je KVM/QEMU kojim upravlja libvirt (`qemu:///system`), s NAT mrežom `default`. VM `sima-vm`: 1 GB RAM,
1 vCPU, disk 10 GB, Ubuntu 24.04. Osnovna slika se preuzima jednom u `/var/lib/libvirt/images`.

## Problem

Procedura sa slajda (Hyper-V Manager, 9 koraka: medij, ime, RAM, mrežni adapter, disk, pokretanje, instalacija) treba
se uraditi na Linuxu, i to tako da se može ponoviti jednom naredbom, a ne klikanjem kroz čarobnjak.

## Pristup rješavanju

| Hyper-V korak | Linux |
|---|---|
| instalacijski medij / ISO | Ubuntu cloud slika (za ISO: `virt-install --cdrom`) |
| New Virtual Machine, ime i lokacija | `virt-install --name sima-vm`, disk u `/var/lib/libvirt/images` |
| RAM 1024 MB | `--memory 1024` |
| mrežni adapter | `--network network=default` |
| novi virtuelni disk | `qemu-img create -f qcow2 -b osnovna-slika ... 10G` |
| pokreni nakon kreiranja | `virt-install` je pokreće sam |
| interaktivna instalacija | cloud-init pri prvom pokretanju (korisnik `student` sa SSH ključem) |

`plan` provjerava preduslove (`/dev/kvm`, libvirt, mreža `default`, `virt-install`, SSH ključ) i ispisuje naredbe;
`up` pravi i pokreće VM i čeka IP adresu; `status` pokazuje stanje i naredbe za upravljanje (Start, Shut Down, Turn Off,
Checkpoint = `virsh snapshot-create-as`).

## Arhitektonske odluke

- **Cloud slika + cloud-init umjesto ISO instalacije:** instalacija traje sekunde umjesto 20 minuta i ne traži
  interaktivni rad, pa VM može napraviti cijela grupa na nastavi. Isti pristup koristi i RuO repozitorij.
- **qcow2 s osnovnom slikom kao podlogom (backing file):** disk VM-a čuva samo razlike, pa više VM-ova dijeli jednu
  preuzetu sliku, a brisanje VM-a ne briše preuzetu sliku.
- **libvirt `qemu:///system` i mreža `default`:** isti stek kao `virt-manager` (grafičko sučelje nalik Hyper-V
  Manageru), pa student može nastaviti rad i iz GUI-ja.

## Dizajnerske odluke

- Osnovni cilj (`make v2-p6`) ništa ne pravi: provjera preduslova i plan rade i na računaru bez KVM-a.
- Zaglavlje skripte i opis daju tabelu Hyper-V -> Linux, jer studenti dolaze sa Windows procedurom sa slajdova.
- `down` ne briše osnovnu sliku (~600 MB) osim uz `SVE=1`, da ponovno pravljenje VM-a ne preuzima sliku iznova.

## Implementacijske odluke

- Tip OS-a: `ubuntu24.04` ako ga osinfo baza poznaje, inače `generic`, jer starije distribucije nemaju zapis za
  Ubuntu 24.04 i `virt-install` bi odbio pokretanje.
- SSH ključ se uzima od korisnika koji je pozvao `sudo` (`SUDO_USER`), ne od root-a.
- IP adresa se čeka do 2 minute preko `virsh domifaddr` (DHCP zakup libvirt mreže).
- Prije brisanja VM-a brišu se njeni snapshotovi, jer `virsh undefine` odbija VM koji ih ima.

Napomena: `v2-p6-up` nije pokretan u razvojnom okruženju (nema KVM-a); `make v2-p6` jeste.

## Pokretanje

```bash
make v2-p6           # preduslovi i plan (ništa se ne pravi)
make v2-p6-up        # preuzimanje slike, VM, IP adresa (sudo, KVM)
make v2-p6-status
make v2-p6-clean     # SVE=1 briše i osnovnu sliku
```
