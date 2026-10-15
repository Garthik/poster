#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
"${COMPOSE[@]}" --profile replica --profile restore down
# NO -v: volumes remain intact.
