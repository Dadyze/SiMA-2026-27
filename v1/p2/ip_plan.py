#!/usr/bin/env python3
"""v1/p2: logičko segmentiranje IPv4 LAN mreže (VLSM) i IP plan mreže.

Zadatak s vježbi: podijeliti 192.168.0.0/24 na dvije podmreže: segment_1 do 100 računara, segment_2 do 50 računara.

  python3 ip_plan.py                                        zadatak s vježbi (jednake podmreže, kao na vježbama)
  python3 ip_plan.py --vlsm                                 isti zadatak, svaka podmreža samo onolika koliko treba
  python3 ip_plan.py 10.10.0.0/23 uprava:120 proizvodnja:200 gosti:60 --vlsm     vlastiti zadatak
  python3 ip_plan.py ... --md ip-plan.md                     zapiši i IP plan (Markdown tabela) u datoteku

Postupak (segmenti od najvećeg prema najmanjem, da podmreže budu poravnate):
  1. broj bita za hostove h: najmanji h za koji je 2^h - 2 >= broj računara (mrežna i broadcast adresa se ne dodjeljuju)
     jednake podmreže: h se računa za najveći segment i koristi za sve; --vlsm: h se računa za svaki segment posebno
  2. dužina maske = 32 - h
  3. podmreža počinje na prvoj slobodnoj adresi koja je djeljiva veličinom bloka 2^h
"""
import argparse
import ipaddress
import math
import sys


def bitovi(adresa: ipaddress.IPv4Address) -> str:
    b = f"{int(adresa):032b}"
    return ".".join(b[i:i + 8] for i in range(0, 32, 8))


def bita_za(n: int) -> int:
    return max(2, math.ceil(math.log2(n + 2)))           # +2: mrežna i broadcast adresa


def segmentiraj(mreza: ipaddress.IPv4Network, zahtjevi, vlsm=False):
    """zahtjevi: lista (ime, broj_racunara); vraća listu (ime, broj, podmreza)."""
    rezultat, slobodna = [], int(mreza.network_address)
    najveci = bita_za(max(n for _, n in zahtjevi))
    for ime, n in sorted(zahtjevi, key=lambda z: -z[1]):
        h = bita_za(n) if vlsm else najveci
        blok = 2 ** h
        pocetak = -(-slobodna // blok) * blok             # zaokruži naviše na višekratnik bloka
        podmreza = ipaddress.IPv4Network((pocetak, 32 - h))
        if not podmreza.subnet_of(mreza):
            sys.exit(f"Segment '{ime}' ({n} računara) ne stane u {mreza}: povećati mrežu ili smanjiti segmente.")
        rezultat.append((ime, n, podmreza))
        slobodna = pocetak + blok
    return rezultat


def ispis(mreza, segmenti, vlsm):
    nacin = "VLSM: svaka podmreža onolika koliko treba" if vlsm else "jednake podmreže (maska prema najvećem segmentu)"
    print(f"Mreža: {mreza}  ({mreza.num_addresses} adresa), {nacin}\n")
    for ime, n, p in segmenti:
        h = 32 - p.prefixlen
        hostovi = list(p.hosts())
        print(f"== {ime}: potrebno {n} računara")
        print(f"   bita za hostove: {h}   (2^{h} = {2 ** h}, upotrebljivo {2 ** h - 2} >= {n});  dužina maske: 32 - {h} = {p.prefixlen}")
        print(f"   maska: /{p.prefixlen} = {p.netmask}   ({bitovi(p.netmask)})")
        print(f"   adresa podmreže: {p.network_address}   ({bitovi(p.network_address)})")
        print(f"   opseg hostova:   {hostovi[0]} - {hostovi[-1]}   ({len(hostovi)} adresa)")
        print(f"   broadcast:       {p.broadcast_address}")
        print(f"   rezerva:         {len(hostovi) - n} adresa za rast\n")
    zauzeto = sum(p.num_addresses for _, _, p in segmenti)
    print(f"Iskorišteno {zauzeto} od {mreza.num_addresses} adresa; slobodno {mreza.num_addresses - zauzeto} za buduće segmente.")


def ip_plan(segmenti):
    """IP plan: tabela uređaja s adresama. Ruter = prva adresa, serveri i štampači statički, ostatak DHCP."""
    redovi = ["| Segment | Uređaj | IP adresa | Maska | Gateway | Dodjela |", "|---|---|---|---|---|---|"]
    for vlan, (ime, n, p) in enumerate(segmenti, start=1):
        h = list(p.hosts())
        gw = h[0]
        staticki = [("ruter (gateway)", h[0]), ("server", h[1]), ("mrežni štampač", h[2]), ("upravljivi svič", h[3])]
        for uredjaj, ip in staticki:
            redovi.append(f"| {ime} (VLAN {vlan * 10}) | {uredjaj} | {ip} | /{p.prefixlen} | {gw} | statička |")
        redovi.append(f"| {ime} (VLAN {vlan * 10}) | klijenti ({n}) | {h[4]} - {h[-1]} | /{p.prefixlen} | {gw} | DHCP |")
    return "\n".join(redovi)


def main():
    ap = argparse.ArgumentParser(description="Segmentiranje IPv4 mreže (VLSM) i IP plan")
    ap.add_argument("mreza", nargs="?", default="192.168.0.0/24")
    ap.add_argument("segmenti", nargs="*", default=["segment_1:100", "segment_2:50"], help="ime:broj_racunara")
    ap.add_argument("--vlsm", action="store_true", help="svaka podmreža samo onolika koliko treba (umjesto jednakih)")
    ap.add_argument("--md", help="zapiši IP plan u Markdown datoteku")
    a = ap.parse_args()

    mreza = ipaddress.IPv4Network(a.mreza, strict=False)
    zahtjevi = []
    for s in a.segmenti:
        ime, _, n = s.rpartition(":")
        if not ime or not n.isdigit():
            sys.exit(f"Pogrešan segment '{s}': oblik je ime:broj_racunara")
        zahtjevi.append((ime, int(n)))

    segmenti = segmentiraj(mreza, zahtjevi, a.vlsm)
    ispis(mreza, segmenti, a.vlsm)
    plan = ip_plan(segmenti)
    print("\nIP plan mreže (tabela svih mrežnih uređaja s adresama):\n")
    print(plan)
    if a.md:
        with open(a.md, "w", encoding="utf-8") as f:
            f.write(f"# IP plan mreže {mreza}\n\n{plan}\n")
        print(f"\nIP plan zapisan u {a.md}")


if __name__ == "__main__":
    main()
