---
title: kora_dealership
sidebar_position: 1
---

# kora_dealership

`kora_dealership` adds vehicle dealerships to Kora servers. Admins build dealerships in an in-game creator (zone, vehicle list, display placements, spawn points, staff points). Customers browse display vehicles, swap what a display shows, test drive, buy, or make offers. Owned dealerships get staff sales and an owner management portal (employees, permissions, funds, stock orders, offers, display editing). All checks (distance, permissions, prices, stock, money) are enforced on the server.

The resource declares `provide 'qb-vehicleshop'` and emits `qb-vehicleshop:server:onVehiclePurchased` after each purchase. See [Compatibility](./compatibility.md).

Current version: see `version` in `fxmanifest.lua`.

## Dealership types

| Type | Meaning |
| --- | --- |
| `public` | Anyone can buy. Stock is unlimited (stored as 9999 per vehicle). |
| `for_sale` | Has a `price` and no owner. The creator can set it, but no gameplay in this resource lets a player buy the dealership (see [Troubleshooting](./troubleshooting.md)). |
| `owned` | Has an owner (a citizenid), employees, a balance, finite stock, management and sale points, and offers. |

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

## Installation

1. Place the resource in your resources folder and ensure it after its dependencies:

   ```cfg
   ensure kora_lib
   ensure kora_sql
   ensure kora_core
   ensure kora_vehiclekeys
   ensure kora_target
   ensure kora_dealership
   ```

2. No SQL import is needed. On start `kora_sql` creates the three `kora_dealership*` tables and adds missing columns. With `Config.UsePDM` (default `true`) it also seeds a public `pdm` dealership if missing.
3. Grant the ACE named by `Config.adminPermission` (default `admin`) to your admins, for example `add_ace group.admin admin allow`. See [Permissions](./permissions.md).
4. Make sure vehicles exist in the `kora_core` shared `vehicles` registry with a `price` of at least 1; other models are ignored when saving vehicle lists.
5. Review [Configuration](./configuration.md).

## Testing

- `bash test/run.sh` runs the offline Lua checks (`test/catalog.lua`, `test/purchased_event.lua`, `test/schema.lua`) with stubs. It does not start FiveM or touch SQL.
- `tests/checklist-vehicles.feature` holds manual QA scenarios for `kora_qa` (registered with `qa_feature` in `fxmanifest.lua`).

## Pages

- [Features](./features.md) - what players, staff, owners and admins can do
- [Configuration](./configuration.md) - every `Config` option
- [Commands](./commands.md) - the creator command
- [Permissions](./permissions.md) - admin ACE, owner, and employee permissions
- [Events and callbacks](./events.md) - server callbacks, net events, state bags
- [Database](./database.md) - tables, columns and external tables used
- [User interface](./ui.md) - creator, showroom, sales, and management apps
- [Compatibility](./compatibility.md) - `qb-vehicleshop` provide and purchase event
- [Troubleshooting](./troubleshooting.md) - caveats and common problems

This resource exposes no exports.
