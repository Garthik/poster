#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lab6/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
command -v openssl >/dev/null || { echo 'openssl is required' >&2; exit 127; }
# Reject accidental secret placement on the repository/DrvFS filesystem.
case "$(realpath -m "$TICKET_SECRETS_DIR")/" in
  "$(realpath "$ROOT_DIR")/"*|/mnt/*) echo 'Secrets must be outside Git, on the WSL Linux filesystem' >&2; exit 2 ;;
esac
umask 077
mkdir -p "$LAB6_PRIVATE"
chmod 700 "$LAB6_PRIVATE"
if [[ -e "$LAB6_PRIVATE/root-user" || -e "$LAB6_PRIVATE/root-password" || -e "$LAB6_PRIVATE/app-password" || -e "$LAB6_PRIVATE/rs-keyfile" ]]; then
  require_secrets
  echo "Existing private files retained: $LAB6_PRIVATE"
  exit 0
fi
printf 'lab6_root\n' > "$LAB6_PRIVATE/root-user"
openssl rand -hex 24 > "$LAB6_PRIVATE/root-password"
openssl rand -hex 24 > "$LAB6_PRIVATE/app-password"
openssl rand -base64 756 > "$LAB6_PRIVATE/rs-keyfile"
chmod 600 "$LAB6_PRIVATE/"*
echo "Created credentials and replica-set key outside Git: $LAB6_PRIVATE"
