# v1-p4: VLAN-ovi i pristup internetu iz VLAN podmreža preko zajedničkog rutera

## Postavka

Segmenti iz `v1-p2` (192.168.0.0/24 podijeljena na dvije /25) postaju VLAN-ovi na jednom upravljivom sviču:

```
         VLAN 10 (uprava) 192.168.0.0/25          VLAN 20 (gosti) 192.168.0.128/25
         pc1 .10    pc2 .11                       pc3 .130    pc4 .131
           p1 |       | p2                          p3 |        | p4      access portovi (untagged)
          [================== svič (bridge, VLAN filtering) ==================]
                                  | p5  trunk (tagged 10 i 20)
                               [ruter]  eth0.10 192.168.0.1, eth0.20 192.168.0.129
                                  | wan 203.0.113.2/30 (NAT)
                               [internet]  198.51.100.10
```

## Problem

Podjela adresa na papiru (v1-p2) ne razdvaja ništa: na običnom sviču gost koji sam sebi postavi adresu uprave odmah je
"unutra". Treba: (1) stvarno razdvojiti segmente na sloju 2 (VLAN), (2) omogućiti promet između njih i prema internetu
preko jednog rutera, (3) gostima dati internet, ali ne i pristup upravi (zahtjev iz projektnog zadatka).

## Pristup rješavanju

1. Svič bez VLAN-ova (svi portovi u VLAN 1): gost s "pozajmljenom" adresom uprave pinga pc1. Problem je dokazan.
2. Kreiranje VLAN-ova i access portova, istim koracima kao u web sučelju sviča sa slajdova
   (Create VLAN, Link Type Access, Untagged): `bridge vlan add dev pN vid X pvid untagged`, uklanjanje VLAN-a 1.
3. Trunk port prema ruteru nosi oba VLAN-a označena (802.1Q tagged).
4. Izolacija: unutar VLAN-a radi; gost s adresom uprave više ne vidi pc1 (svič ne pušta okvir u drugi VLAN);
   između VLAN-ova nema prometa jer nema rutera.
5. Router on a stick: podsučelja `eth0.10` i `eth0.20` na jednom fizičkom portu su gatewayi segmenata, uz
   `ip_forward=1`; traceroute pokazuje skok preko rutera.
6. Internet: bez NAT-a internet ne zna put nazad do privatnih adresa; nftables `masquerade` na WAN-u to rješava.
7. Izolovana mreža za goste: firewall na ruteru propušta `established,related`, a odbacuje nove konekcije VLAN 20 -> VLAN 10.
   Uprava može do gostiju (odgovor prolazi kao established), gosti ne mogu do uprave, internet imaju oba.

## Arhitektonske odluke

- **Bridge s `vlan_filtering`** je pravi 802.1Q svič u jezgri: PVID, untagged/tagged portovi i VLAN tabela ponašaju se
  kao na upravljivom sviču sa slajdova, pa se koncepti preslikavaju jedan na jedan.
- **Router on a stick** (jedan trunk, VLAN podsučelja) umjesto posebnog porta po VLAN-u: odgovara slajdu "pristup
  internetu iz VLAN podmreža preko zajedničkog rutera" i najčešćoj maloj instalaciji (jedan ruter, jedan svič).
- **Internet kao poseban namespace bez rute nazad** (203.0.113.0/30, 198.51.100.10): bez toga se ne bi vidjelo zašto
  je NAT potreban.
- Izolacija gostiju je **na ruteru (sloj 3)**, a ne na sviču: VLAN razdvaja segmente, a politika ko smije kome je
  posao rutera/firewalla.

## Dizajnerske odluke

- Isti "napad" (gost s adresom uprave) se ponavlja prije i poslije VLAN-ova: ista naredba, različit ishod.
- Adrese i VLAN brojevi su isti kao u IP planu iz `v1-p2`, da se vidi put od proračuna do konfiguracije.
- Firewall je stateful (`ct state established,related accept` prije `drop`), da uprava može inicirati promet prema
  gostima; bez toga bi pravilo slučajno prekinulo i odgovore.

## Implementacijske odluke

- Portovi se pune iz jedne liste `ns:vlan:adresa:gateway`, pa isti podaci služe za adresiranje, access portove i rute.
- Na početku se provjerava podrška jezgre: ako `vlan_filtering` nije podržan (npr. neke WSL2 jezgre), skripta to kaže i
  čisti se umjesto da padne na pola; `00-setup.sh` istu provjeru radi unaprijed.
- `modprobe 8021q` se pokušava tiho, jer je modul na nekim sistemima ugrađen, a na nekim se mora učitati.
- NAT i firewall su naredbe `nft add ...` korak po korak (a ne jedna datoteka), da se na nastavi vidi svako pravilo;
  na kraju `nft list ruleset` pokazuje rezultat kao cjelinu.

Napomena: ovaj lab nije pokretan u razvojnom okruženju (jezgra bez VLAN filtriranja na bridge-u).

## Pokretanje

```bash
make v1-p4          # shema laba
make v1-p4-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v1-p4-clean
```
