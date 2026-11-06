#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
"$ROOT/install.sh"

printf '\nНажмите любую клавишу, чтобы закрыть это окно…'
read -n 1 -s -r
printf '\n'
