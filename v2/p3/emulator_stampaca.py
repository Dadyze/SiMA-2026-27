#!/usr/bin/env python3
"""v2/p3: "mrežni štampač" za vježbu. Sluša na TCP portu 9100 (RAW / JetDirect, kao većina mrežnih štampača)
i svaki primljeni posao "odštampa" u datoteku u izlaznom direktoriju.

  python3 emulator_stampaca.py <izlazni_direktorij> [adresa] [port]
"""
import os
import socket
import sys
import time

izlaz = sys.argv[1]
adresa = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
port = int(sys.argv[3]) if len(sys.argv) > 3 else 9100
os.makedirs(izlaz, exist_ok=True)

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind((adresa, port))
s.listen(5)
print(f"štampač spreman na {adresa}:{port}", flush=True)
while True:
    veza, klijent = s.accept()
    podaci = b""
    while blok := veza.recv(65536):
        podaci += blok
    veza.close()
    n = len(os.listdir(izlaz)) + 1
    ime = os.path.join(izlaz, f"posao-{n:03d}.txt")
    with open(ime, "wb") as f:
        f.write(podaci)
    print(f"{time.strftime('%H:%M:%S')} odštampano {len(podaci)} B od {klijent[0]} -> {ime}", flush=True)
