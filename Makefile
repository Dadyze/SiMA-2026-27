# Sistemska i mrežna administracija 2026/27: primjeri s vježbi (Linux)
# Pokretanje: `make help`. Naredbe se ispisuju prije izvršavanja, da se vidi šta se radi.
# Napomena: umjesto tabulatora koristi se ">" kao prefiks naredbi (.RECIPEPREFIX).

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX := >
.DEFAULT_GOAL := help

EX ?=
PAUZA ?= 0
KVAR ?=
# v1-p2: vlastiti zadatak segmentiranja, npr. make v1-p2 MREZA=10.10.0.0/23 SEG="uprava:120 proizvodnja:200"
MREZA ?= 192.168.0.0/24
SEG ?= segment_1:100 segment_2:50

banner = printf '\n\033[1;36m== %s\033[0m\n' '$(1)'
# provjera alata prije izvršavanja: jasna poruka umjesto kriptične greške
need = command -v $(1) >/dev/null || PATH="$$PATH:/usr/sbin:/sbin" command -v $(1) >/dev/null || { echo "Nedostaje '$(1)'. Pokreni: ./00-setup.sh"; exit 1; }
need_libvirt = virsh -c qemu:///system list >/dev/null 2>&1 || { echo "libvirt ne radi (virsh -c qemu:///system list). Pokreni ./00-setup.sh i pogledaj README.md (systemd/KVM)"; exit 1; }
# ispis zaglavlja skripte (shema laba i upotreba), bez izvršavanja
shema = sed -n '2,/^set -/p' $(1) | grep '^\#' | sed 's/^\# \{0,1\}//'
SUDO = sudo PAUZA=$(PAUZA)

.PHONY: help setup check run all lab-all clean-all ssh-key \
  v1-p1 v1-p1-lab v1-p1-netplan v1-p1-clean v1-p2 v1-p3 v1-p3-lab v1-p3-clean \
  v1-p4 v1-p4-lab v1-p4-clean v1-p5 v1-p5-lab v1-p5-clean v1-clean \
  v2-p1 v2-p1-lab v2-p1-kvar v2-p1-dijagnoza v2-p1-rjesenje v2-p1-clean v2-p2 \
  v2-p3 v2-p3-lab v2-p3-clean v2-p4 v2-p4-lab v2-p4-clean v2-p5 v2-p5-lab v2-p5-clean \
  v2-p6 v2-p6-up v2-p6-status v2-p6-clean v2-clean \
  v3-p1 v3-p1-apply v3-p1-clean v3-p2 v3-p2-apply v3-p2-clean v3-p3 v3-p3-lab v3-p3-clean \
  v3-p4 v3-p4-lab v3-p4-clean v3-p5 v3-p5-lab v3-p5-clean v3-clean

##@ Pomoć
help: ## ovaj popis
> @awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5)} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)
> @printf '\nPrimjer: make v1-p1   ili   make run EX=v1-p1.   PAUZA=1 (npr. make v1-p1-lab PAUZA=1) čeka Enter nakon svakog koraka.\n'

setup: ## instalira sve alate (00-setup.sh)
> ./00-setup.sh

check: ## provjera da li su alati instalirani
> @for t in git make python3 ip bridge ping traceroute dig dnsmasq dhcpcd nft lpadmin mdadm mkfs.btrfs sfdisk mkfs.vfat e4defrag clamscan iostat virsh virt-install qemu-img; do \
>   if command -v $$t >/dev/null || PATH="$$PATH:/usr/sbin:/sbin" command -v $$t >/dev/null; then printf '  \033[32mok\033[0m     %s\n' $$t; else printf '  \033[33mnema\033[0m   %s\n' $$t; fi; done

run: ## make run EX=v1-p1 (isto što i make v1-p1)
> @test -n "$(EX)" || { echo "Upotreba: make run EX=v1-p1"; exit 1; }
> @$(MAKE) --no-print-directory $(EX)

ssh-key:
> @test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519

##@ Vježba 1 (V6): konfigurisanje mreže i mrežno okruženje (lab u Linux network namespace-ovima; -lab traži sudo)
v1-p1: ## mrežne postavke računara: adrese, gateway, DNS, ARP (ipconfig /all), samo čita
> bash v1/p1/konfiguracija.sh pregled
v1-p1-lab: ## [lab] statička adresa, gateway, DNS, pa DHCP (DISCOVER/OFFER/REQUEST/ACK, zakup, APIPA)
> @$(call need,dnsmasq)
> @$(call need,dhcpcd)
> $(SUDO) bash v1/p1/konfiguracija.sh vjezba
v1-p1-netplan: ## trajna konfiguracija: provjera netplan primjera (statički i DHCP), bez primjene
> bash v1/p1/konfiguracija.sh provjera
v1-p1-clean: ## briše lab v1-p1
> -sudo bash v1/p1/konfiguracija.sh down

v1-p2: ## logičko segmentiranje 192.168.0.0/24 (100 + 50 računara) i IP plan; MREZA=... SEG="ime:broj ..."
> @$(call banner,jednake podmreže (kao na vježbama))
> python3 v1/p2/ip_plan.py $(MREZA) $(SEG)
> @$(call banner,VLSM: svaka podmreža onolika koliko treba)
> python3 v1/p2/ip_plan.py $(MREZA) $(SEG) --vlsm

v1-p3: ## kaskadna hijerarhijska LAN (3 nivoa svičeva): ispis naredbi (DRY=1), ništa se ne mijenja
> DRY=1 bash v1/p3/kaskada.sh up
v1-p3-lab: ## [lab] gradi kaskadu, MAC tabele, promet kroz nivoe, kvar uplinka
> $(SUDO) bash v1/p3/kaskada.sh vjezba
v1-p3-clean: ## briše lab v1-p3
> -sudo bash v1/p3/kaskada.sh down

v1-p4: ## VLAN-ovi: shema laba (ništa se ne mijenja)
> @$(call shema,v1/p4/vlan.sh)
v1-p4-lab: ## [lab] svič s VLAN 10/20, access i trunk portovi, router on a stick, NAT, izolacija gostiju
> @$(call need,nft)
> $(SUDO) bash v1/p4/vlan.sh vjezba
v1-p4-clean: ## briše lab v1-p4
> -sudo bash v1/p4/vlan.sh down

v1-p5: ## bekap internet link (dual WAN): shema laba (ništa se ne mijenja)
> @$(call shema,v1/p5/bekap.sh)
v1-p5-lab: ## [lab] dva ISP-a, metrike ruta, kvar linka, nadzor i automatski failover
> @$(call need,traceroute)
> $(SUDO) bash v1/p5/bekap.sh vjezba
v1-p5-clean: ## briše lab v1-p5
> -sudo bash v1/p5/bekap.sh down

v1-clean: v1-p1-clean v1-p3-clean v1-p4-clean v1-p5-clean ## čisti cijelu vježbu 1

##@ Vježba 2 (V7): održavanje mreže i računara (diskovi su datoteke na loop uređajima; -lab traži sudo)
v2-p1: ## dijagnostika LAN mreže: Windows naredbe i Linux ekvivalenti, shema laba
> @$(call shema,v2/p1/dijagnostika.sh)
v2-p1-lab: ## [lab] ping, ip addr, traceroute, ss (LISTEN/ESTAB/TIME-WAIT) na ispravnoj mreži
> @$(call need,dnsmasq)
> $(SUDO) bash v2/p1/dijagnostika.sh vjezba
v2-p1-kvar: ## [lab] ubacuje kvar (slučajan i skriven; KVAR=1..6 bira određeni)
> sudo bash v2/p1/dijagnostika.sh kvar $(KVAR)
v2-p1-dijagnoza: ## [lab] dijagnostika odozdo prema gore: link, adresa, gateway, IP, DNS, servis
> sudo bash v2/p1/dijagnostika.sh dijagnoza
v2-p1-rjesenje: ## [lab] otkriva ubačeni kvar i vraća ispravno stanje
> sudo bash v2/p1/dijagnostika.sh rjesenje
v2-p1-clean: ## briše lab v2-p1
> -sudo bash v2/p1/dijagnostika.sh down

v2-p2: ## pouzdanost složenih sistema: RAID 1 (2 x 0.97) i računar (komponente 0.95), serijski/paralelno
> python3 v2/p2/pouzdanost.py

v2-p3: ## štampači: CUPS, redovi čekanja (lpstat), samo čita
> @$(call need,lpstat)
> bash v2/p3/stampac.sh pregled
v2-p3-lab: ## [lab] mrežni štampač (emulator, port 9100), štampa, zastoji, zaglavljen red
> @$(call need,lpadmin)
> $(SUDO) bash v2/p3/stampac.sh vjezba
v2-p3-clean: ## uklanja štampač vježbe i gasi emulator
> -sudo bash v2/p3/stampac.sh down

v2-p4: ## RAID: postojeći nizovi i diskovi, samo čita
> bash v2/p4/raid1.sh pregled
v2-p4-lab: ## [lab] softverski RAID 1 (mdadm, ili btrfs ako nema md): kvar diska, degradirani rad, zamjena, obnova
> $(SUDO) bash v2/p4/raid1.sh vjezba
v2-p4-clean: ## briše diskove vježbe v2-p4
> -sudo bash v2/p4/raid1.sh down

v2-p5: ## particije i boot: diskovi, MBR/GPT, UEFI/BIOS, fstab, samo čita
> bash v2/p5/particije.sh pregled
v2-p5-lab: ## [lab] MBR (primarne, proširena, logičke), GPT (EFI, sistem, podaci, recovery), UUID i fstab
> @$(call need,sfdisk)
> $(SUDO) bash v2/p5/particije.sh vjezba
v2-p5-clean: ## briše disk vježbe v2-p5
> -sudo bash v2/p5/particije.sh down

v2-p6: ## virtuelna mašina (KVM/libvirt, kao Hyper-V): preduslovi i plan, ništa se ne pravi
> bash v2/p6/vm.sh plan
v2-p6-up: ssh-key ## [opcionalno] preuzme Ubuntu sliku (~600 MB), napravi i pokrene VM (traži KVM)
> @$(call need_libvirt)
> sudo bash v2/p6/vm.sh up
v2-p6-status: ## stanje VM-a i naredbe za upravljanje (start, shutdown, snapshot)
> sudo bash v2/p6/vm.sh status
v2-p6-clean: ## briše VM (osnovna slika ostaje; SVE=1 briše i nju)
> -sudo SVE=$(SVE) bash v2/p6/vm.sh down

v2-clean: v2-p1-clean v2-p3-clean v2-p4-clean v2-p5-clean v2-p6-clean ## čisti cijelu vježbu 2

##@ Vježba 3 (V8): održavanje klijentskog OS-a (Linux)
v3-p1: ## ažuriranje: verzija, dostupna ažuriranja, automatsko ažuriranje, historija + provjera konfiguracije
> bash v3/p1/azuriranje.sh pregled
> bash v3/p1/azuriranje.sh provjera
v3-p1-apply: ## [opcionalno] apt update, simulacija, uključuje unattended-upgrades i probni prolaz
> sudo bash v3/p1/azuriranje.sh apply
v3-p1-clean: ## uklanja postavke koje je dodao v3-p1-apply
> -sudo bash v3/p1/azuriranje.sh down

v3-p2: ## antivirus (ClamAV): vlastiti potpisi, skeniranje, EICAR, karantena (bez interneta, bez sudo)
> @$(call need,clamscan)
> PAUZA=$(PAUZA) bash v3/p2/antimalware.sh vjezba
v3-p2-apply: ## [opcionalno] preuzima službenu bazu potpisa (freshclam, ~200 MB) i skenira njome
> sudo bash v3/p2/antimalware.sh apply
v3-p2-clean: ## briše datoteke vježbe v3-p2
> -bash v3/p2/antimalware.sh down

v3-p3: ## disk: zauzeće, najveći direktoriji, šta se može čistiti, samo čita
> bash v3/p3/disk.sh pregled
v3-p3-lab: ## [lab] automatsko čišćenje (tmpfiles), fragmentacija i defragmentacija (e4defrag), TRIM
> @$(call need,e4defrag)
> $(SUDO) bash v3/p3/disk.sh vjezba
v3-p3-clean: ## briše datoteke vježbe v3-p3
> -sudo bash v3/p3/disk.sh down

v3-p4: ## tačka vraćanja: provjera systemd timera (dnevno) i skripte, ništa se ne instalira
> bash v3/p4/restore.sh provjera
v3-p4-lab: ## [lab] btrfs snapshot kao Restore Point: loša instalacija, vraćanje sistema (podaci ostaju), retencija
> @$(call need,mkfs.btrfs)
> $(SUDO) bash v3/p4/restore.sh vjezba
v3-p4-clean: ## briše disk vježbe v3-p4
> -sudo bash v3/p4/restore.sh down

v3-p5: ## nadzor (Task Manager): opterećenje, memorija, procesi, disk, servisi pri startu, samo čita
> bash v3/p5/nadzor.sh pregled
v3-p5-lab: ## [lab] zaglavljen proces: pronalaženje, prioritet, gašenje; servis pri startu (enable/disable)
> $(SUDO) bash v3/p5/nadzor.sh vjezba
v3-p5-clean: ## uklanja demo servis i procese vježbe v3-p5
> -sudo bash v3/p5/nadzor.sh down

v3-clean: v3-p1-clean v3-p2-clean v3-p3-clean v3-p4-clean v3-p5-clean ## čisti cijelu vježbu 3

##@ Skupno
all: check v1-p1 v1-p1-netplan v1-p2 v1-p3 v1-p4 v1-p5 v2-p1 v2-p2 v2-p3 v2-p4 v2-p5 v2-p6 v3-p1 v3-p2 v3-p3 v3-p4 v3-p5 ## svi osnovni ciljevi redom (ne mijenjaju sistem, osim datoteka v3-p2 u /var/tmp)
> @$(call banner,SVI PRIMJERI ZAVRSENI)
lab-all: ## svi -lab ciljevi redom, svaki se odmah čisti (sudo; bez v2-p6-up, v3-p1-apply, v3-p2-apply)
> @for t in v1-p1 v1-p3 v1-p4 v1-p5 v2-p1 v2-p3 v2-p4 v2-p5 v3-p3 v3-p4 v3-p5; do \
>   $(MAKE) --no-print-directory $$t-lab || echo "!! $$t-lab nije uspio"; $(MAKE) --no-print-directory $$t-clean >/dev/null 2>&1 || true; done
clean-all: v1-clean v2-clean v3-clean ## čišćenje svih primjera
