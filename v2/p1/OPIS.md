# v2-p1: dijagnostika LAN mreže i traženje kvara

## Postavka

```
[pc] 192.168.20.50 --- [ruter] 192.168.20.1 / 203.0.113.2 --- [internet] web klix.ba 198.51.100.10:80
                                                                          DNS 198.51.100.53
```

Na "internetu" rade pravi servisi: web server (python `http.server`) i DNS (dnsmasq) koji `klix.ba` prevodi u
198.51.100.10. Vježba ima dva dijela: naredbe na ispravnoj mreži i traženje ubačenog kvara.

## Problem

Korisnik javlja "nemam interneta, klix.ba ne radi". Isti simptom ima najmanje šest različitih uzroka, od kabla do
aplikacije. Administrator treba sistematičan postupak koji brzo pokaže na kojem sloju je kvar, umjesto nasumičnog
restartovanja.

## Pristup rješavanju

Dio 1 (`v2-p1-lab`), naredbe sa slajdova i njihovi Linux ekvivalenti:
1. `ping 127.0.0.1` (loopback, TCP/IP stek);
2. `ip addr`, `ip route`, `resolv.conf` (Windows `ipconfig /all`);
3. ping vlastite adrese, gatewaya, udaljene IP adrese i imena: svaki provjerava jedan dio puta;
4. izlaz pinga: RTT, TTL (63 = jedan ruter na putu), gubitak paketa; `ping -t 1` izaziva "Time to live exceeded";
5. `traceroute` (Windows `tracert`);
6. `ss` (Windows `netstat -an`): stanja LISTEN, ESTAB i TIME-WAIT se prave namjerno (server sluša, jedna konekcija
   ostaje otvorena, jedna se upravo zatvorila).

Dio 2, kvar:
- `make v2-p1-kvar` ubacuje slučajan i skriven kvar (ili određen: `KVAR=1..6`): prekinut kabl, pogrešan gateway,
  nepostojeći DNS server, adresa iz pogrešne podmreže, ugašen web server, ruter koji ne prosljeđuje (`ip_forward=0`);
- student traži uzrok ručno (`sudo ip netns exec sima-pc bash`) ili pokreće `make v2-p1-dijagnoza`;
- dijagnoza ide **odozdo prema gore** (OSI): link (LOWER_UP) -> loopback i vlastita adresa -> gateway -> udaljena IP ->
  DNS -> servis, staje na prvom neuspjelom koraku i ispisuje vjerovatan uzrok i šta dalje provjeriti;
- `make v2-p1-rjesenje` otkriva koji je kvar bio i vraća ispravno stanje.

## Arhitektonske odluke

- **Pravi servisi umjesto simulacije odgovora:** DNS i HTTP stvarno rade, pa `dig`, `curl` i `ss` pokazuju stvarno
  ponašanje (npr. TIME-WAIT nastaje jer HTTP/1.0 server prvi zatvara konekciju).
- **Kvarovi su stanje laba, ne poseban lab:** isti lab se kvari i popravlja (`ispravno()` vraća sve što bilo koji kvar
  mijenja), pa se vježba može ponavljati bez ponovne izgradnje.
- Svaki kvar je na drugom sloju, pa zajedno pokrivaju cijeli put paketa od kabla do aplikacije.

## Dizajnerske odluke

- Slučajan kvar je **skriven** (ispisuje se samo prijava korisnika), jer je cilj vježbati dijagnostiku, a ne čitati
  rješenje. Određen kvar (`KVAR=n`) je za demonstraciju na nastavi.
- Dijagnoza staje na **prvom** neuspjelom koraku: kod kvara na nižem sloju svi viši koraci bi i tako pali, pa bi njihov
  ispis samo zbunjivao.
- Uz svaki neuspjeh ide i sljedeći korak provjere (npr. kod koraka 4 automatski `traceroute` pokazuje gdje put staje).
- Kvar "ugašen servis" je namjerno uključen: mreža je potpuno ispravna, a korisnik i dalje "nema interneta".

## Implementacijske odluke

- Provjera DNS-a traži da `dig +short` vrati IPv4 adresu (`^[0-9.]+$`), jer `dig` grešku "communications error" piše na
  standardni izlaz, pa samo "ima li izlaza" nije dovoljno.
- Gateway za provjeru se čita iz tabele usmjeravanja računara (`ip route show default`), pa korak 3 otkriva i pogrešan
  gateway i adresu iz pogrešne podmreže.
- ESTAB konekcija se drži bash-ovim `/dev/tcp` u pozadini 15 s, bez dodatnih alata.
- Broj ubačenog kvara se čuva u `/run/sima-v2p1/kvar`; `rjesenje` ga čita, a `ispravno()` ga briše.

## Pokretanje

```bash
make v2-p1               # tabela Windows/Linux naredbi i shema
make v2-p1-lab           # naredbe na ispravnoj mreži (sudo)
make v2-p1-kvar          # slučajan skriven kvar   (make v2-p1-kvar KVAR=3: određen)
make v2-p1-dijagnoza
make v2-p1-rjesenje
make v2-p1-clean
```
