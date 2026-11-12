---
title: "Installation"
sidebar_position: 2
---


# Installation

Kora Dealership is a dealership creator and showroom: an in-game admin tool to draw dealership zones, pick a vehicle list, place display cars and spawn points, plus the customer-facing purchase/test-drive flow, a staff sales target, and (for owned dealerships) an owner management portal. It answers to `qb-vehicleshop` for the legacy `TriggerEvent('qb-vehicleshop:server:onVehiclePurchased', ...)` hook. Server-only persistence; the UI is Kora Lib's AppShell.

## Install Kora Dealership

1. **Add the folder** — Place `kora_dealership` in your resources directory (on the Kora recipe it is `resources/[kora]/kora_dealership`).

2. **Dependencies** — The manifest declares `dependency 'kora_lib'`, `dependency 'kora_sql'` and `dependency 'kora_core'`, and loads `@kora_lib/init.lua` then `@kora_core/init.lua` as shared scripts before `config.lua` and `shared/functions.lua`. The README also lists `kora_vehiclekeys` (keys for delivered vehicles) and `kora_target` (the browse/sales/management targets) as runtime dependencies, though they are not declared as `dependency` lines in the manifest — ensure both before `kora_dealership`.

3. **Start order** — Start after kora_lib, kora_core, kora_sql, kora_vehiclekeys and kora_target.

   ```bash title="server.cfg"
   ensure kora_lib
   ensure kora_core
   ensure kora_sql
   ensure kora_vehiclekeys
   ensure kora_target
   ensure kora_dealership
   ```

4. **Grant the creator permission** — Add the ace named by `Config.adminPermission` (default `admin`) to your admins, e.g. `add_ace group.admin admin allow`. `/dealershipcreator` (the command name is `Config.command`) is registered for everyone, but every creator callback re-checks `IsPlayerAceAllowed(src, Config.adminPermission)` on the server, so opening it without the ace shows nothing usable.

5. **Nothing to import** — On start, kora_sql creates `kora_dealerships`, `kora_dealership_management` and `kora_dealership_offers`, and adds any missing columns to existing ones. With `Config.UsePDM = true` (the default) it also seeds a public `pdm` dealership (a prebuilt vehicle list, zone and placements) if it is missing (kora_sql seeds with `INSERT IGNORE` each boot).

## Dealership types

- `public` — anyone can buy, stock is unlimited (internally treated as 9999 of everything).
- `for_sale` — not yet owned; has a `price` an admin sets, but no public purchase flow is implemented for buying the dealership itself (unclear: no server callback sells a `for_sale` dealership to a player — the type only changes what the creator shows and what `patchDealership` keeps).
- `owned` — has an `owner` (citizen id), employees, a bank-style balance, finite per-vehicle stock, sale/management zones and customer offers.

## If it does not work

- Console prints `kora_sql was unavailable; dealerships are not loaded until restart` if kora_sql was not ready within 60 s at boot — restart kora_dealership once the database is reachable.
- `/dealershipcreator` opens but every list/save action fails silently (notices say the admin permission is required): grant `Config.adminPermission`.
- A showroom, sales or management interaction point does not appear: the dealership needs a zone drawn first (placements/spawns/zones can only be added inside the zone, see "Zone-gated point placement" below), or `kora_target`/`kora_vehiclekeys` is not running.

## Requirements

Declared in `fxmanifest.lua` (`dependency`):

| Resource | Used for |
| --- | --- |
| `kora_lib` | NUI apps, callbacks, notifications, zones, entities, raycast, distance checks, locales |
| `kora_sql` | Schema creation (`ensureTables`) and all queries |
| `kora_core` | Player data, money (`removeMoney`, `addMoney`), shared vehicles (`getShared`, `allShared`) |

Used but not declared as dependencies:

| Resource | Used for |
| --- | --- |
| `kora_vehiclekeys` | `exports.kora_vehiclekeys:giveKeys` for test-drive and purchased vehicles (server) |
| `kora_target` | Target zones at management and sale points, and the "browse" option on display vehicles (client) |

It also reads and writes the `players` and `player_vehicles` tables owned by other resources. See [Database](./database.md).

## Vehicle registry

Make sure vehicles exist in the `kora_core` shared `vehicles` registry with a `price` of at least 1; other models are ignored when saving vehicle lists. Then review [Configuration](./configuration.md).

## Testing

- `bash test/run.sh` runs the offline Lua checks (`test/catalog.lua`, `test/purchased_event.lua`, `test/schema.lua`) with stubs. It does not start FiveM or touch SQL.
- `tests/checklist-vehicles.feature` holds manual QA scenarios for `kora_qa` (registered with `qa_feature` in `fxmanifest.lua`).
