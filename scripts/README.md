# GHCR prune helper

Ten folder zawiera skrypt pomocniczy do hurtowego usuwania wersji kontenera (container package) z GitHub Container Registry (ghcr.io). Skrypt jest przeznaczony do uruchamiania lokalnie i wymaga tokena PAT z odpowiednimi uprawnieniami.

Pliki:
- scripts/ghcr_prune.sh - główny skrypt (dry-run domyślnie)

Użycie:

1. Przygotuj token:

```bash
export GITHUB_TOKEN=ghp_xxx
```

Token musi mieć uprawnienia: `read:packages` i `delete:packages` (oraz `repo` dla prywatnych repo).

2. Dry-run (pokazuje, co zostałoby usunięte):

```bash
./scripts/ghcr_prune.sh OWNER PACKAGE 3
```

3. Rzeczywiste usunięcie:

```bash
./scripts/ghcr_prune.sh OWNER PACKAGE 3 --exec
```

Przykład:

```bash
GITHUB_TOKEN=ghp_xxx ./scripts/ghcr_prune.sh jurekl my-image 3 --exec
```

Ostrzeżenia:
- Skrypt usuwa wersje pakietu globalnie (wszystkie tagi) poza N najnowszymi. Jeśli chcesz zachować np. konkretne tagi lub filtrować per-tag/branch, zgłoś to a dopiszę filtry.
- Jeśli operacja usuwania zwróci błąd HTTP 403/404 — sprawdź uprawnienia tokena i czy pakiet należy do wskazanego ownera.
