#!/usr/bin/env bash
set -euo pipefail

exec ngrok http --domain=synergistic-wilburn-overclean.ngrok-free.dev 3000
