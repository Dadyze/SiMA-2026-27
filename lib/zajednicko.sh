# lib/zajednicko.sh: pomoćne funkcije za sve vježbe (uključuje se s: source "$(dirname "$0")/../../lib/zajednicko.sh")
# Svaka naredba se ispisuje prije izvršavanja, da se na nastavi vidi šta se radi.
export PATH="$PATH:/usr/sbin:/sbin"
PAUZA="${PAUZA:-0}"

korak() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
info()  { printf '   \033[2m%s\033[0m\n' "$*"; }
ok()    { printf '   \033[32mOK\033[0m   %s\n' "$*"; }
ne()    { printf '   \033[31mNE\033[0m   %s\n' "$*"; }
pauza() { [ "$PAUZA" = 1 ] && read -r -p "   (Enter za nastavak) " _ || true; }

# kmd [ns] naredba...: ispiše naredbu i izvrši je; ako je prvi argument ime namespace-a (sima-*), izvrši je u njemu.
# Greška naredbe ne prekida vježbu (dio vježbi namjerno pokazuje greške).
kmd() {
  if [[ "${1:-}" == sima-* ]] && ip netns list 2>/dev/null | grep -qw -- "$1"; then
    local ns="$1"; shift; echo "[${ns#sima-}]\$ $*"; ip netns exec "$ns" "$@"
  else echo "\$ $*"; "$@"; fi
  return 0
}

# ping1 ns cilj [opis]: jedan ping s kratkim čekanjem, ispis ODGOVARA / NE ODGOVARA
ping1() {
  local ns="$1" cilj="$2" opis="${3:-}"
  if ip netns exec "$ns" ping -c1 -W1 "$cilj" >/dev/null 2>&1; then ok "[${ns#sima-}] ping $cilj ${opis}"
  else ne "[${ns#sima-}] ping $cilj ${opis}"; fi
}

treba_root() { [ "$(id -u)" = 0 ] || { echo "Treba root: sudo $0 ${1:-}"; exit 1; }; }
treba() { command -v "$1" >/dev/null 2>&1 || { echo "Nedostaje '$1'. Pokreni: ./00-setup.sh"; exit 1; }; }

# ns_obrisi ime...: briše namespace-ove (ako postoje) i gasi procese koji su u njima ostali (dnsmasq, http server...)
ns_obrisi() {
  local ns
  for ns in "$@"; do
    ip netns list | grep -qw -- "$ns" || continue
    ip netns pids "$ns" 2>/dev/null | xargs -r kill 2>/dev/null || true
    ip netns del "$ns" && echo "obrisan $ns"
  done
  return 0
}

# veza ns1 if1 ns2 if2: "kabl" (veth par) između dva namespace-a
veza() { ip link add "$2" netns "$1" type veth peer name "$4" netns "$3"; ip -n "$1" link set "$2" up; ip -n "$3" link set "$4" up; }

# ns_novi ime: namespace s uključenim loopbackom
ns_novi() { ip netns add "$1"; ip -n "$1" link set lo up; }
