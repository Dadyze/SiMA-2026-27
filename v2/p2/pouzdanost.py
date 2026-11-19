#!/usr/bin/env python3
"""v2/p2: određivanje pouzdanosti složenih sistema (serijska, paralelna i kombinovana veza).

  R  pouzdanost (vjerovatnoća da komponenta radi u periodu, npr. godinu dana),  N = 1 - R  nepouzdanost

  serijska veza   (sistem radi samo ako rade SVE komponente):      R = R1 * R2 * ... * Rn
  paralelna veza  (sistem otkaže samo ako otkažu SVE komponente):  N = N1 * N2 * ... * Nn,  R = 1 - (1-R1)(1-R2)...(1-Rn)

  python3 pouzdanost.py                      primjeri s vježbi
  python3 pouzdanost.py serijski 0.95 0.9 0.99
  python3 pouzdanost.py paralelno 0.97 0.97
"""
import sys
from functools import reduce


def serijski(*r):
    return reduce(lambda a, b: a * b, r, 1.0)


def paralelno(*r):
    return 1 - reduce(lambda a, b: a * b, (1 - x for x in r), 1.0)


def pct(r):
    return f"{r * 100:.4g} %"


def raid1():
    print("== Primjer 1: RAID 1 (ogledalo) od dva diska, pouzdanost svakog diska 0.97 (3 % kvarova godišnje)")
    r1 = r2 = 0.97
    n = (1 - r1) * (1 - r2)
    print("   Sistem je u kvaru samo ako otkažu OBA diska (paralelna veza):")
    print(f"   N = N1 * N2 = (1 - 0.97) * (1 - 0.97) = 0.03 * 0.03 = {n:.4f}")
    print(f"   R = 1 - N = 1 - {n:.4f} = {1 - n:.4f} = {pct(1 - n)}")
    print(f"   Jedan disk: {pct(r1)}  ->  RAID 1: {pct(paralelno(r1, r2))}   (vjerovatnoća gubitka podataka pada {0.03 / n:.0f} puta)\n")


def racunar():
    p = 0.95
    komponente = ["napajanje", "matična ploča", "procesor", "RAM", "disk"]
    print(f"== Primjer 2: računar kao složen sistem, pouzdanost svake komponente Pi = {p}")
    r = serijski(*[p] * len(komponente))
    print(f"   Komponente su u serijskoj vezi ({', '.join(komponente)}): kvar bilo koje zaustavlja računar")
    print(f"   R = {' * '.join([str(p)] * len(komponente))} = {p}^{len(komponente)} = {r:.4f} = {pct(r)}")
    print("   Serijska veza je uvijek MANJE pouzdana od najslabije komponente.\n")

    print("   Poboljšanje: redundantno napajanje (2 paralelno) i RAID 1 (2 diska paralelno):")
    napajanje = paralelno(p, p)
    disk = paralelno(p, p)
    r2 = serijski(napajanje, p, p, p, disk)
    print(f"   napajanje: 1 - (1-{p})^2 = {napajanje:.4f};  diskovi: 1 - (1-{p})^2 = {disk:.4f}")
    print(f"   R = {napajanje:.4f} * {p} * {p} * {p} * {disk:.4f} = {r2:.4f} = {pct(r2)}")
    print("   Paralelna veza je uvijek VIŠE pouzdana od najpouzdanije komponente.\n")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] in ("serijski", "paralelno"):
        r = [float(x) for x in sys.argv[2:]]
        if not all(0 <= x <= 1 for x in r):
            sys.exit("Pouzdanost je broj od 0 do 1 (npr. 0.95)")
        rez = serijski(*r) if sys.argv[1] == "serijski" else paralelno(*r)
        print(f"{sys.argv[1]} {r}:  R = {rez:.6f} = {pct(rez)}   N = {1 - rez:.6f}")
    elif len(sys.argv) == 1:
        raid1()
        racunar()
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
