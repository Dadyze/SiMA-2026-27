"""Generiše PDF bilješke s vježbi iz HTML izvora pomoću Edge/Chrome/Chromium (headless).

Upotreba:  python3 docs/src/build.py          (iz korijena repozitorija)
Izlaz:     docs/SiMA - Vjezbe.pdf

Izvor su dijelovi uvod.html, vjezba1.html, vjezba2.html, vjezba3.html (spajaju se tim redom).
Isječci koda se ne kopiraju ručno, nego se pri izgradnji uzimaju iz stvarnih datoteka repozitorija, pa dokument
uvijek prikazuje kod koji se zaista izvršava. Oznaka u HTML-u:

  <!--KOD putanja | početak | kraj | naslov-->

  putanja   datoteka u repozitoriju (npr. v1/p1/konfiguracija.sh)
  početak   tekst prve linije isječka (prva linija koja ga sadrži)
  kraj      tekst zadnje linije isječka (prva sljedeća linija koja ga sadrži); "=}" = linija koja je tačno "}";
            prazno = samo jedna linija
  naslov    tekst u zaglavlju bloka (npr. "Isječak 3 · DHCP klijent")
"""
import html
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

SRC = Path(__file__).resolve().parent
OUT = SRC.parent
REPO = OUT.parent
DIJELOVI = ["uvod.html", "vjezba1.html", "vjezba2.html", "vjezba3.html"]
CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    "google-chrome", "chromium", "chromium-browser", "microsoft-edge",
]


def jezik(putanja: str) -> str:
    if "upgrades" in putanja:
        return "apt.conf"
    return {".sh": "bash", ".py": "python", ".yaml": "yaml", ".conf": "tmpfiles.d", ".service": "systemd",
            ".timer": "systemd"}.get(Path(putanja).suffix, "tekst")


def isjecak(m: re.Match) -> str:
    putanja, pocetak, kraj, naslov = (x.strip() for x in m.group(1).split("|"))
    linije = (REPO / putanja).read_text(encoding="utf-8").splitlines()
    try:
        i = next(n for n, l in enumerate(linije) if pocetak in l)
    except StopIteration:
        sys.exit(f"{putanja}: nema linije s tekstom '{pocetak}'")
    j = i
    if kraj:
        try:
            if kraj.startswith("="):      # "=}" : linija koja je tačno "}" (kraj funkcije)
                j = next(n for n in range(i + 1, len(linije)) if linije[n] == kraj[1:])
            else:
                j = next(n for n in range(i + 1, len(linije)) if kraj in linije[n])
        except StopIteration:
            sys.exit(f"{putanja}: nakon '{pocetak}' nema linije s tekstom '{kraj}'")
    kod = "\n".join(linije[i:j + 1])
    duzina = " long" if j - i > 40 else ""
    return (f'<div class="code{duzina}"><div class="hd"><span>{jezik(putanja)} · {putanja}:{i + 1}-{j + 1}</span>'
            f'<span>{html.escape(naslov)}</span></div><pre>{html.escape(kod)}</pre></div>')


def style_comments(src: str) -> str:
    """Komentari (# ...) u blokovima koda dobivaju drugu boju."""
    def pre(m):
        body = re.sub(r'(^|\s)(#\s[^\n]*)$', lambda k: k.group(1) + '<span class="c">' + k.group(2) + '</span>',
                      m.group(2), flags=re.M)
        return m.group(1) + body + '</pre>'
    return re.sub(r'(<div class="code[^"]*">.*?<pre>)(.*?)</pre>', pre, src, flags=re.S)


def main():
    tekst = "\n".join((SRC / d).read_text(encoding="utf-8") for d in DIJELOVI)
    tekst = re.sub(r"<!--KOD(.*?)-->", isjecak, tekst, flags=re.S)
    tekst = style_comments(tekst)
    tmp = SRC / "_build.html"
    tmp.write_text(tekst, encoding="utf-8")
    if "--html" in sys.argv:
        print("napravljen", tmp)
        return
    browser = next((c for c in CANDIDATES if os.path.exists(c) or shutil.which(c)), None)
    if not browser:
        sys.exit("Nije pronađen Edge/Chrome/Chromium.")
    out = OUT / "SiMA - Vjezbe.pdf"
    out.unlink(missing_ok=True)
    profile = SRC / "_profile"
    subprocess.run([browser, "--headless", "--disable-gpu", "--no-sandbox", "--no-pdf-header-footer",
                    f"--user-data-dir={profile}", f"--print-to-pdf={out}", tmp.as_uri()], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # novi headless način vraća kontrolu prije nego što je PDF zapisan: čekati da veličina postane stabilna
    last, stable = -1, 0
    for _ in range(120):
        size = out.stat().st_size if out.exists() else -1
        stable = stable + 1 if size > 0 and size == last else 0
        if stable >= 3:
            break
        last = size
        time.sleep(0.5)
    shutil.rmtree(profile, ignore_errors=True)
    if not out.exists():
        sys.exit(f"PDF nije napravljen: {out}")
    tmp.unlink()
    print("napravljen", out)


if __name__ == "__main__":
    main()
