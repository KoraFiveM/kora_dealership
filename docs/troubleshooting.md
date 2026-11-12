---
title: Troubleshooting
sidebar_position: 13
---

# Troubleshooting

## Nothing loads after start

The server prints `kora_sql was unavailable` when `kora_sql` is not ready within 60 seconds, or `schema failed` when table creation fails. Dealerships are not loaded until a restart in either case. Make sure `kora_sql` starts first.

## "Admin permission required."

The ACE named in `Config.adminPermission` is not granted to the player. See [Permissions](./permissions.md).

## No target options appear

`kora_target` and `kora_vehiclekeys` are not declared dependencies. Make sure they are started. Management and sale target zones exist only on `owned` dealerships and only after points were added.

## Cannot add points

Points added by owners and employees must be inside the dealership zone. If a dealership has no zone, an admin must draw it first.

## "There is no free spawn point right now."

Every spawn point has a vehicle within `Config.spawnClearance`. Add more spawn points or clear the area.

## Offers

An offer is accepted only when the offeror has enough cash (not bank) and the vehicle is in stock. Auto-accepted offers that cannot complete are denied. Accepted offers produce a garaged vehicle, not a spawned one.

## Known limitations

- A `for_sale` dealership has a price but no purchase flow in this resource.
- The creator vehicle list has no price edit or remove control wired up in the UI (the list item emits an action the creator does not handle), so vehicle prices and removal cannot currently be changed from the creator.
- Display swaps are kept in memory only and reset on resource restart.
