#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
"${LUA:-lua}" test/catalog.lua
"${LUA:-lua}" test/purchased_event.lua
"${LUA:-lua}" test/schema.lua
"${LUA:-lua}" test/showroom.lua
"${LUA:-lua}" test/test_drive.lua
