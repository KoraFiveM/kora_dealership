---
title: Troubleshooting
sidebar_position: 13
---

# Troubleshooting

## Nothing loads after start

The server prints `kora_sql was unavailable` when `kora_sql` is not ready within 60 seconds, `schema failed` when dealership table creation fails, or `player tables unavailable` when `players` or `player_vehicles` do not appear within 60 seconds. Dealerships are not loaded or published in any of these cases. Start `kora_sql` and the resources that own the player tables first, then restart `kora_dealership`.

## "Admin permission required."

The ACE named in `Config.adminPermission` is not granted to the player. See [Permissions](./permissions.md).

## No target options appear

Make sure the declared `kora_target` and `kora_vehiclekeys` dependencies are installed and started. Management and sale target zones exist only on `owned` dealerships and only after points were added.

## Cannot add points

Points added by owners and employees must be inside the dealership zone. If a dealership has no zone, an admin must draw it first.

## "There is no free spawn point right now."

Every spawn point has a vehicle within `Config.spawnClearance`. Add more spawn points or clear the area.

## Offers

An offer is accepted only when the offeror has enough cash and the vehicle is in stock. The automatic worker denies offers that fail these eligibility checks. If a database write rolls back or the dealership is busy, the offer stays pending for a later attempt. Accepted offers produce a garaged vehicle.

## Settlement needs review

Bank refunds, withdrawals, and commissions can be credited by character ID if the player disconnects. Cash credits for staff sales still require the character to be online.

The server logs the dealership and transaction details when it cannot confirm a commit or complete a required player credit. Writes to that dealership pause until resource restart. Check the recorded plate or offer, dealership totals and player account before issuing a refund or commission manually, then restart the resource to reload the database state.

## Known limitations

- A `for_sale` dealership has a price but no purchase flow in this resource.
- Display swaps are kept in memory only and reset on resource restart.
