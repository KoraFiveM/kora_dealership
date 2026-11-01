#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
"${LUA:-lua}" test/catalog.lua
"${LUA:-lua}" test/purchased_event.lua
