#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/migrations"
DB_URL="${DB_URL:-postgresql://ticket_app:ticket_app@localhost:5432/ticket_platform}"
TARGET=""

usage() {
    cat <<USAGE
Usage: $0 [--target VERSION]

Environment:
  DB_URL   PostgreSQL connection string.

Examples:
  ./scripts/migrate.sh
  DB_URL=postgresql://user:pass@localhost:5432/db ./scripts/migrate.sh
  ./scripts/migrate.sh --target 001_init
USAGE
}

while (($#)); do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value" >&2; exit 2; }
            TARGET="$2"
            shift 2
            ;;
        --target=*)
            TARGET="${1#*=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

command -v psql >/dev/null 2>&1 || {
    echo "ERROR: psql is required" >&2
    exit 127
}

mapfile -t MIGRATION_FILES < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' -printf '%f\n' | sort)

((${#MIGRATION_FILES[@]} > 0)) || {
    echo "ERROR: no migration files found in $MIGRATIONS_DIR" >&2
    exit 1
}

VERSIONS=()
for file in "${MIGRATION_FILES[@]}"; do
    VERSIONS+=("${file%.sql}")
done

if [[ -n "$TARGET" ]]; then
    target_found=false
    for version in "${VERSIONS[@]}"; do
        if [[ "$version" == "$TARGET" ]]; then
            target_found=true
            break
        fi
    done
    if [[ "$target_found" != true ]]; then
        echo "ERROR: migration target '$TARGET' does not exist" >&2
        printf 'Available migrations:\n' >&2
        printf '  %s\n' "${VERSIONS[@]}" >&2
        exit 1
    fi
fi

has_schema_migrations=false
if psql "$DB_URL" -Atqc \
    "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'app' AND table_name = 'schema_migrations');" \
    2>/dev/null | grep -qx 't'; then
    has_schema_migrations=true
fi

APPLIED=()
if [[ "$has_schema_migrations" == true ]]; then
    mapfile -t APPLIED < <(
        psql "$DB_URL" -Atqc \
            "SELECT version FROM app.schema_migrations ORDER BY version;"
    )
fi

is_applied() {
    local wanted="$1"
    local item
    for item in "${APPLIED[@]}"; do
        [[ "$item" == "$wanted" ]] && return 0
    done
    return 1
}

has_version() {
    local wanted="$1"
    local item
    for item in "${VERSIONS[@]}"; do
        [[ "$item" == "$wanted" ]] && return 0
    done
    return 1
}

if [[ -n "$TARGET" ]]; then
    target_index=-1
    for i in "${!VERSIONS[@]}"; do
        if [[ "${VERSIONS[$i]}" == "$TARGET" ]]; then
            target_index="$i"
            break
        fi
    done

    for applied in "${APPLIED[@]}"; do
        if has_version "$applied"; then
            applied_index=-1
            for i in "${!VERSIONS[@]}"; do
                if [[ "${VERSIONS[$i]}" == "$applied" ]]; then
                    applied_index="$i"
                    break
                fi
            done
            if (( applied_index > target_index )); then
                echo "ERROR: database is already newer than target '$TARGET' (applied '$applied')" >&2
                exit 1
            fi
        else
            echo "ERROR: database contains unknown migration '$applied'" >&2
            exit 1
        fi
    done
fi

for i in "${!MIGRATION_FILES[@]}"; do
    file="${MIGRATION_FILES[$i]}"
    version="${VERSIONS[$i]}"

    if [[ -n "$TARGET" && "$i" -gt "$target_index" ]]; then
        break
    fi

    if is_applied "$version"; then
        echo "SKIP  $version"
        continue
    fi

    echo "APPLY $version"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$MIGRATIONS_DIR/$file"

    if ! psql "$DB_URL" -Atqc \
        "SELECT 1 FROM app.schema_migrations WHERE version = '$version';" \
        | grep -qx '1'; then
        echo "ERROR: migration '$version' completed but did not register itself in app.schema_migrations" >&2
        exit 1
    fi

    APPLIED+=("$version")
done

echo "Migration check passed. Applied versions:"
if ((${#APPLIED[@]} == 0)); then
    echo "  <none>"
else
    printf '  %s\n' "${APPLIED[@]}"
fi
