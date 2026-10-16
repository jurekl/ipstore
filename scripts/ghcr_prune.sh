#!/usr/bin/env bash
set -euo pipefail

# ghcr_prune.sh
# Skrypt usuwa wersje (versions) container package w GHCR pozostawiając N najnowszych.
# Domyślnie robi dry-run; aby wykonać usunięcie użyj flagi --exec.

usage() {
  cat <<EOF
Usage: $0 OWNER PACKAGE [KEEP=3] [--exec]
  OWNER     - nazwa użytkownika lub organizacji (np. jurekl)
  PACKAGE   - nazwa pakietu/container w GHCR (np. my-app)
  KEEP      - ile najnowszych wersji zostawić (domyślnie 3)
  --exec    - wykonaj faktyczne usunięcie; bez tej flagi to dry-run
Notes:
  - Wymaga GITHUB_TOKEN w środowisku z zakresami read:packages i delete:packages.
  - Skrypt spróbuje najpierw listować wersje jako user; jeśli 404, spróbuje org.
EOF
  exit 1
}

if [ $# -lt 2 ]; then usage; fi

OWNER="$1"
PACKAGE="$2"
KEEP="${3:-3}"
EXEC=false
if [ "${KEEP}" = "--exec" ]; then
  EXEC=true
  KEEP=3
fi
# if 4th arg is --exec
if [ $# -ge 4 ] && [ "$4" = "--exec" ]; then EXEC=true; fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Błąd: ustaw GITHUB_TOKEN przed uruchomieniem (export GITHUB_TOKEN=... )" >&2
  exit 2
fi

API="https://api.github.com"
HDRS=(-H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json")

# funkcja do pobierania wersji (próbuje user, potem org)
get_versions() {
  local type="$1" owner="$2" package="$3" page=1 per_page=100
  versions=()
  while :; do
    resp=$(curl -sS "${HDRS[@]}" "$API/${type}s/${owner}/packages/container/${package}/versions?per_page=${per_page}&page=${page}")
    # jeśli pusty lub error, przerwij
    if echo "$resp" | jq -e . >/dev/null 2>&1; then
      # sprawdź czy to tablica
      if [ "$(echo "$resp" | jq 'type')" = "\"array\"" ]; then
        cnt=$(echo "$resp" | jq 'length')
        if [ "$cnt" -eq 0 ]; then break; fi
        versions+=( "$resp" )
        ((page++))
      else
        # prawdopodobnie object z message (błąd)
        echo "$resp"
        return 1
      fi
    else
      return 1
    fi
  done
  # połączenie stron w jedną tablicę
  echo "${versions[@]}" | jq -s 'add'
}

# najpierw spróbuj jako user, jeśli 404 to jako org
if versions_json=$(get_versions user "${OWNER}" "${PACKAGE}" 2>/dev/null); then
  owner_type="user"
else
  if versions_json=$(get_versions org "${OWNER}" "${PACKAGE}" 2>/dev/null); then
    owner_type="org"
  else
    echo "Nie mogę pobrać wersji pakietu. Sprawdź OWNER, PACKAGE i uprawnienia tokena." >&2
    exit 3
  fi
fi

# Z wersji wydobądź id i created_at
all_versions=$(echo "$versions_json" | jq -r '.[] | {id: .id, created_at: .created_at, name: (.metadata.container.tags // ["<no-tag>"] | join(",")) } | @base64')
# Zbuduj listę posortowaną malejąco po created_at
mapfile -t rows < <(echo "$versions_json" | jq -r '.[] | "\(.created_at) \(.id) \(.metadata.container.tags // ["<no-tag>"] | join(",") )"' | sort -r)

total=${#rows[@]}
if [ "$total" -le "$KEEP" ]; then
  echo "Jest $total wersji, trzymamy $KEEP — nic do usunięcia."
  exit 0
fi

echo "Znaleziono $total wersji pakietu ${OWNER}/${PACKAGE} (typ: $owner_type)."
echo "Zachowujemy $KEEP najnowszych, do usunięcia zostanie $((total - KEEP))."
echo
echo "Najnowsze (pierwsze $KEEP):"
for i in $(seq 0 $((KEEP-1))); do
  echo "  ${rows[$i]}"
done

echo
echo "Do usunięcia (pozostałe):"
to_delete=()
for i in $(seq $KEEP $((total-1))); do
  line="${rows[$i]}"
  id=$(echo "$line" | awk '{print $2}')
  to_delete+=("$id")
  echo "  $line"
done

if [ "${EXEC}" = false ]; then
  echo
  echo "Dry-run: nic nie zostało usunięte. Uruchom ponownie z flagą --exec aby faktycznie usuwać."
  exit 0
fi

echo
echo "Wykonuję usunięcie..."
for id in "${to_delete[@]}"; do
  del_url="$API/${owner_type}s/${OWNER}/packages/container/${PACKAGE}/versions/${id}"
  http_status=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "${HDRS[@]}" "$del_url" || true)
  if [ "$http_status" = "204" ]; then
    echo "  Usunięto version id=$id"
  else
    echo "  Błąd usuwania id=$id (HTTP $http_status)"
  fi
done

echo "Gotowe."
