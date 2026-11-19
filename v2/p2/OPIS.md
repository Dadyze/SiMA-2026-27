# v2-p2: određivanje pouzdanosti složenih sistema

## Postavka

Pouzdanost R je vjerovatnoća da komponenta radi u posmatranom periodu (npr. godinu dana), nepouzdanost N = 1 - R.
Dva primjera s vježbi:
1. RAID 1 od dva diska, pouzdanost svakog 0.97 (3 % kvarova godišnje);
2. računar kao složen sistem čije komponente imaju pouzdanost 0.95.

## Problem

Treba izračunati pouzdanost sistema iz pouzdanosti komponenti i pokazati kako način povezivanja (serijski ili
paralelno/redundantno) mijenja rezultat, odnosno zašto se kritične komponente (diskovi, napajanje) udvostručuju.

## Pristup rješavanju

- **Serijska veza** (sistem radi samo ako rade sve komponente): R = R1 * R2 * ... * Rn.
  Računar od 5 komponenti po 0.95: 0.95^5 = 0.7738 (77.38 %), manje od najslabije komponente.
- **Paralelna veza** (sistem otkaže samo ako otkažu sve): N = N1 * N2 * ... * Nn, R = 1 - N.
  RAID 1: N = 0.03 * 0.03 = 0.0009, R = 0.9991 (99.91 %): vjerovatnoća gubitka podataka pada 33 puta.
- **Kombinovana veza:** isti računar s redundantnim napajanjem i RAID 1 (dva bloka paralelno unutar serijske veze):
  0.9975 * 0.95^3 * 0.9975 = 0.8531 (85.31 %).
- Proizvoljan račun: `python3 v2/p2/pouzdanost.py serijski 0.95 0.9 0.99` ili `paralelno 0.97 0.97`.

## Arhitektonske odluke

- Dvije čiste funkcije (`serijski`, `paralelno`) od kojih se gradi svaki složen sistem: kombinovana veza je samo
  `serijski(paralelno(...), ..., paralelno(...))`, isto kao blok-dijagram pouzdanosti na tabli.
- Bez vanjskih biblioteka i bez root-a: radi i na ispitnom računaru.

## Dizajnerske odluke

- Ispis prati postupak s table korak po korak (N1, N2, N, R), s međurezultatima, da student uporedi svoj rad.
- Uz svaki rezultat je pravilo koje se iz njega uči ("serijska veza je manje pouzdana od najslabije komponente",
  "paralelna je pouzdanija od najpouzdanije").
- Treći primjer (poboljšani računar) povezuje teoriju s praksom iz istih vježbi: redundantna napojna jedinica i RAID 1
  (`v2-p4`).

## Implementacijske odluke

- `functools.reduce` nad proizvoljnim brojem argumenata, pa funkcije rade za n komponenti.
- Ulaz se provjerava (0 <= R <= 1); pogrešan poziv ispisuje uputstvo (docstring modula).
- Procenti se ispisuju na 4 značajne cifre (`:.4g`), pa 0.9991 ostaje 99.91 %, a ne 99.910000 %.

## Pokretanje

```bash
make v2-p2
python3 v2/p2/pouzdanost.py paralelno 0.97 0.97
```
