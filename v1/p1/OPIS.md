# v1-p1: konfigurisanje mrežnog sučelja (statička adresa, gateway, DNS, DHCP)

## Postavka

Dva Linux network namespace-a spojena jednim virtuelnim kablom (veth par):

```
[sima-pc] eth0 ---- veth ---- eth0 [sima-rtr]  192.168.1.1/24
                                    DHCP + DNS server (dnsmasq), zakup 24h
                                    "server na internetu" 198.51.100.10 (na lo rutera)
```

`sima-pc` je klijentski računar koji na početku ima sučelje bez adrese i u stanju DOWN. `sima-rtr` je kućni/uredski ruter:
gateway za LAN, DNS server (`server.lan`, `klix.ba`) i DHCP server s opsegom 192.168.1.100-199.

## Problem

Računar treba dovesti od "kabl je uključen, ali ništa ne radi" do punog pristupa (lokalna mreža, internet, imena).
Studenti trebaju vidjeti da su to **tri odvojena podešavanja** (adresa/maska, gateway, DNS) i da svaki nedostatak ima
drugačiji simptom, te razliku između ručne (statičke) i automatske (DHCP) konfiguracije.

## Pristup rješavanju

1. Početno stanje: sučelje postoji, DOWN, bez adrese.
2. Statička adresa `192.168.1.50/24`: jezgra sama dodaje rutu za podmrežu. Gateway odgovara, server izvan LAN-a ne.
3. Zadani put (`default via 192.168.1.1`): server izvan LAN-a odgovara.
4. DNS: bez `nameserver` linije `dig klix.ba` ne radi iako ping na IP radi ("nemam interneta" je često samo DNS).
5. DHCP: adresa se briše, `dhcpcd` dobija adresu, gateway i DNS; u logu servera se vidi DORA razmjena
   (DISCOVER, OFFER, REQUEST, ACK), a u `ip addr` oznaka `dynamic` i `valid_lft` (trajanje zakupa).
6. Tabela zakupa na serveru (MAC, IP, vrijeme isteka).
7. DHCP server se gasi: klijent dobija samo link-local 169.254.x.x (APIPA); statička adresa i dalje radi.

`pregled` radi isto čitanje na stvarnom računaru (Linux "ipconfig /all"), a `provjera` validira netplan datoteke za trajnu
konfiguraciju naredbom `netplan generate` u privremenom korijenskom direktoriju.

## Arhitektonske odluke

- **Network namespace umjesto VM-ova ili prave mreže:** pravi izolovani mrežni stek (sučelja, rute, ARP, resolv.conf)
  pokreće se za milisekunde, ne treba hipervizor ni dodatni hardver, a mreža računara (i SSH/WSL veza) ostaje netaknuta.
- **Ruter i servisi u istom namespace-u:** jedan `sima-rtr` glumi ruter, DHCP i DNS kao većina kućnih rutera, pa je
  topologija najmanja moguća za sve tri teme.
- **"Internet" je adresa na loopbacku rutera** (198.51.100.10, TEST-NET-2 iz RFC 5737): dovoljno da se vidi razlika
  između "u podmreži" i "izvan podmreže" bez trećeg namespace-a.

## Dizajnerske odluke

- Redoslijed koraka prati redoslijed kvarova u praksi (adresa, pa gateway, pa DNS) i svaki korak završava pingom
  **OK/NE**, pa se uzrok i posljedica vide odmah.
- Zakup 24h je izabran jer je to tipična postavka (pitanje s vježbi: "koliko dugo host zadržava dinamičku adresu").
- Korak bez DHCP servera namjerno pokazuje APIPA adresu jer je to simptom koji studenti najčešće sretnu u praksi.
- Statički i DHCP netplan primjer su odvojene datoteke da se mogu uporediti red po red.

## Implementacijske odluke

- **DNS po namespace-u:** `/etc/netns/sima-pc/resolv.conf` (ip netns exec ga montira preko /etc/resolv.conf), pa se DNS
  klijenta mijenja bez diranja DNS-a računara. Za upite se koristi `dig`, ne `getent`, jer na sistemima sa
  systemd-resolved `getent` ide preko lokalnog socketa računara i zaobišao bi namespace.
- **dnsmasq** s `--conf-file=/dev/null --no-resolv --no-hosts --bind-interfaces`: ne čita konfiguraciju računara i ne
  zauzima port 53 izvan namespace-a; `dnsmasq-base` nema sistemski servis koji bi se sukobio s systemd-resolved.
- **dhcpcd** se pokreće s `-c /bin/true` (bez hook skripti, pa ne mijenja ime ni DNS računara) i u vlastitom mount
  namespace-u s tmpfs preko `/var/lib/dhcpcd`, pa zakupi i DUID ne ostaju na računaru. `-1 -B` čeka prvi zakup i
  završava (uključujući ARP provjeru zauzetosti adrese).
- Sve naredbe idu kroz `kmd` iz `lib/zajednicko.sh`, koja ispisuje `[pc]$ naredba` prije izvršavanja.

## Pokretanje

```bash
make v1-p1            # pregled stvarnog računara (samo čita)
make v1-p1-lab        # vježba (sudo), PAUZA=1 čeka Enter
make v1-p1-netplan    # provjera netplan datoteka
make v1-p1-clean
```
