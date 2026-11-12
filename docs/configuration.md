---
title: Configuration
sidebar_position: 7
---

# Configuration

All options are in `config.lua` (the `Config` table, shared between client and server). The file ends by passing `Config` through `Kora.config.adopt` when available, so values may also be overridden by `kora_lib` config. Locale strings are in `locales/en.lua`.

## General

| Option | Default | Description |
| --- | --- | --- |
| `Config.command` | `'dealershipcreator'` | Creator command name. |
| `Config.adminPermission` | `'admin'` | ACE required for creator callbacks. |
| `Config.maxPrice` | `5000000` | Maximum vehicle price in the creator and for offers and price overrides. |
| `Config.UsePDM` | `true` | Seed a public `pdm` dealership (full vehicle list, display placements and spawns) when it does not exist. When `false` the seed is skipped. |
| `Config.categories` | 23 class names | Names for GTA vehicle classes (index is class id plus 1) used to group the showroom. Do not reorder. |

## Limits for client-saved data

| Option | Default | Description |
| --- | --- | --- |
| `Config.maxPlacements` | `50` | Display placements per dealership. |
| `Config.maxSpawns` | `20` | Spawn points per dealership. |
| `Config.maxZones` | `10` | Management points, and separately sale points. |
| `Config.maxZonePoints` | `32` | Points in the dealership polygon. |
| `Config.maxBalance` | `2000000000` | Dealership balance cap (the column is `int`). |
| `Config.maxStock` | `100` | Stock cap per vehicle on non-public dealerships. |

## Customer actions

| Option | Default | Description |
| --- | --- | --- |
| `Config.swapDistance` | `6.0` | Max distance from the placement to swap. |
| `Config.swapCooldown` | `1000` | Milliseconds between swaps per player. |
| `Config.testDriveDistance` | `5.0` | Max distance from the display vehicle for test drive, purchase and offer. |
| `Config.testDriveSeconds` | `120` | Server cut-off for a test drive. |
| `Config.testBucketBase` | `100000` | Routing bucket base for test drives (plus server id). |
| `Config.testSpawn` | `x=-1574.22, y=-3008.77, z=13.94, w=227.21` | Where test vehicles spawn. |
| `Config.spawnClearance` | `3.0` | A spawn point is blocked when a vehicle is this close. |
| `Config.rateLimits` | `testDrive=3000, purchase=2000, offer=5000, funds=1000` | Per-player cooldowns in milliseconds. |
| `Config.maxPendingOffers` | `5` | Open offers one player may have. |
| `Config.offerVehicleState` | `'garaged'` | `player_vehicles.state` for a vehicle won through an accepted offer. |
| `Config.autoConfirmOffersDays` | `14` | Days until a pending offer is auto-accepted. `0` or less disables it. |
| `Config.autoConfirmCheckSeconds` | `600` | Interval of the due-offer check (minimum 10). |

## Management portal

| Option | Default | Description |
| --- | --- | --- |
| `Config.managementDistance` | `5.0` | Server-checked distance from a management point. |
| `Config.managementTargetRadius` | `1.5` | Target zone radius at each management point. |
| `Config.maxEmployees` | `20` | Employees per dealership. |
| `Config.orderPriceMultiplier` | `0.7` | Wholesale cost multiplier of the list price per ordered vehicle (minimum 1 each). |
| `Config.maxOrderQuantity` | `10` | Vehicles per order. |
| `Config.offersPageLimit` | `50` | Offers shown per list (pending and history). |
| `Config.employeePermissions` | four entries | Permission values and labels. See [Permissions](./permissions.md). |

## Sales target

| Option | Default | Description |
| --- | --- | --- |
| `Config.saleDistance` | `5.0` | Server-checked distance from a sale point. |
| `Config.saleTargetRadius` | `1.5` | Target zone radius at each sale point. |
| `Config.nearbyCustomerDistance` | `8.0` | How close a customer must be to be listed. Also used when adding employees. |
| `Config.saleConfirmTimeout` | `60` | Seconds before a seller's lock on an unanswered sale expires. |
| `Config.paymentMethods` | `cash`, `card` | Options shown to the customer. The server maps `cash` to cash and `card` to bank; other values are rejected. |

## Per-dealership settings

Stored in the database per owned dealership (see [Database](./database.md)), edited by the owner in the portal: `maxPriceOverride` (default 10), `commission` (default 5) and `employeeDiscount` (default 5), each 0 to 100.
