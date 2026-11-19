# v1/projekat: idejni projekat LAN mreže (grupni projekat)

**Investitor:** „Preduzeće0” d.o.o. Zenica
**Cilj:** idejno rješenje LAN mreže za novu poslovnu zgradu (tlocrt s radnim mjestima i sektorima je u prilogu na vježbama).
**Projektant:** grupa od 4 studenta.

## Zahtjevi

1. Efikasno radno okruženje: performanse (brzina, dostupnost, raspoloživost, pouzdanost), dijeljenje diskova i štampača,
   serverske usluge, mrežna štampa, zajednički pristup internetu, pristup SQL Server bazi na serveru, Wi-Fi pristup internetu,
   **izolovani Wi-Fi za goste**, zaštita mreže, bekap rješenje, lako održavanje i skalabilnost.
2. Jedna LAN mreža s dvije Wi-Fi mreže; aktivna oprema u prostoriji „IT soba”.
3. Daljinski pristup LAN mreži preko interneta.
4. Internet pristup s **bekap linkom**; portiri bežični pristup kroz Wi-Fi za goste.
5. Oprema s najpovoljnijim odnosom cijene i kvaliteta.

## Šta projekat sadrži (struktura dokumenta)

| # | Dio | Pomoć iz repozitorija |
|---|---|---|
| 1 | Fizička šema mreže: horizontalne trase i raspored pasivne opreme na tlocrtu | `v1/p3` (hijerarhija: jezgro, pristupni svičevi, najviše 3 nivoa) |
| 2 | Logička šema: povezivanje uređaja i putanja podataka | `v1/p3`, `v1/p4` |
| 3 | IP plan: tabela svih uređaja s adresama i lokacijama | `python3 v1/p2/ip_plan.py <mreža> <segment:broj> ... --md ip-plan.md` |
| 4 | Segmentiranje: VLAN za upravu, proizvodnju, goste ... | `v1/p4` (VLAN, router on a stick, izolacija gostiju) |
| 5 | Internet i bekap link (dual WAN, failover) | `v1/p5` |
| 6 | Specifikacija pasivne opreme (kablovi Cat6, utičnice, patch paneli, ormar) | |
| 7 | Specifikacija aktivne opreme (ruter, svičevi, AP, UPS) s cijenama | |
| 8 | Konfiguracija servera i klijenata (hardver i softver) | `v2`, `v3` |
| 9 | Dinamički plan projekta: trajanje svih faza (Gantt dijagram) | |

Primjer IP plana za zgradu s tri segmenta:

```bash
python3 v1/p2/ip_plan.py 192.168.0.0/23 uprava:60 proizvodnja:150 gosti:40 --vlsm --md ip-plan.md
```
