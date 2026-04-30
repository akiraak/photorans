#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/client"

exec npx expo start --dev-client --clear
