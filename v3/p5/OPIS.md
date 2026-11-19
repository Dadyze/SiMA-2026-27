# v3-p5: nadgledanje performansi (Task Manager) i programi koji se pokreću sa sistemom (Startup)

## Postavka

`pregled` radi na stvarnom računaru (samo čita). Vježba pravi "zaglavljen" proces `sima-zaglavljen` (beskonačna petlja)
i, ako radi systemd, instalira demo servis `sima-demo.service` koji svakih 10 s upiše red u dnevnik.

## Problem

Računar je spor. Treba utvrditi da li je uzrok CPU, memorija ili disk, pronaći proces koji troši resurse, smiriti ga ili
ugasiti, i kontrolisati šta se pokreće sa sistemom (sporo pokretanje, programi koje niko ne koristi).

## Pristup rješavanju

`pregled`, Linux ekvivalenti kartica Task Managera:
1. opterećenje (`uptime`, load average za 1/5/15 min) u odnosu na broj jezgri (`nproc`);
2. memorija (`free -h`): "available" je stvarno slobodna memorija, buff/cache jezgra oslobađa po potrebi;
3. procesi koji najviše troše CPU i memoriju (`ps --sort`);
4. trenutna slika (`top -b -n1`);
5. CPU, memorija i disk kroz vrijeme (`vmstat 1 3`: `r` čekanje na CPU, `wa` čekanje na disk);
6. opterećenje diskova (`iostat -x`: `%util` blizu 100 = disk je usko grlo);
7. Startup: omogućeni servisi (`systemctl list-unit-files --state=enabled`), trajanje pokretanja
   (`systemd-analyze`, `blame`) i `~/.config/autostart`.

`vjezba`:
1. Zaglavljen proces troši cijelo jezgro; `ps` sortiran po CPU-u ga stavlja na vrh.
2. Prioritet: `renice 19` (najmanji prioritet), pa ostali programi dobijaju CPU prije njega.
3. Gašenje: `kill` (TERM, uredno), objašnjenje `kill -9` i `pkill` po imenu.
4. Servis pri startu: instalacija `sima-demo.service`, `systemctl enable --now`, status i dnevnik (`journalctl -u`).
5. Isključivanje iz pokretanja: `systemctl disable --now` (Startup "Disabled").

## Arhitektonske odluke

- **Standardni alati (procps, sysstat, systemd)** umjesto htop-a ili GUI alata: postoje na svakom serveru, rade preko
  SSH-a i daju ispis koji se može uporediti i u skripti.
- **Problem se pravi namjerno i kontrolisano** (jedan proces, jedno jezgro, ime `sima-zaglavljen`), pa se uvijek može
  pronaći i sigurno ugasiti, i na nastavi je ishod isti kod svih.
- **Startup na Linuxu = systemd servisi:** program koji se pokreće sa sistemom je unit s `WantedBy=multi-user.target`,
  a `enable`/`disable` je isto što i Enabled/Disabled u Task Manageru.

## Dizajnerske odluke

- Tabela "Task Manager -> Linux" je u zaglavlju skripte jer studenti dolaze s Windows procedurom sa slajda.
- Prioritet (`renice`) se pokazuje prije gašenja: u praksi se proces koji radi koristan posao često samo "smiri", a ne gasi.
- Uz `kill` se objašnjava razlika TERM/KILL: prvo se traži uredno gašenje, prisilno tek ako ne uspije.
- Servis ima `Restart=on-failure`: systemd ga sam ponovo pokreće ako padne, što je razlika u odnosu na običan program
  iz Startup liste.

## Implementacijske odluke

- Zaglavljen proces se pokreće kao `exec -a sima-zaglavljen sh -c 'while :; do :; done'`: vlastito ime procesa za
  `ps`/`pkill`, bez dodatnih alata za opterećenje (stress i sl.).
- `iostat` ispis se svodi na uređaj, r/s, w/s i %util i preskaču se loop uređaji, da stane na ekran.
- Ako systemd ne radi (WSL bez `systemd=true`), dio sa servisom se preskače uz poruku umjesto da vježba padne.
- `down` gasi proces i po PID-u i po imenu, onemogućava i briše servis i radi `daemon-reload`, pa na računaru ne ostaje ništa.

Napomena: dio sa servisom (koraci 4 i 5) nije pokretan u razvojnom okruženju (bez systemd-a); ostatak jeste.

## Pokretanje

```bash
make v3-p5          # pregled stvarnog računara (samo čita)
make v3-p5-lab      # vježba (sudo), PAUZA=1 čeka Enter
make v3-p5-clean
```
