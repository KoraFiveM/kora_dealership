---
title: Features
sidebar_position: 6
---

# Features

## Creator (admins)

- Create, edit and delete dealerships with `/dealershipcreator`. A new dealership gets an id derived from its name (lower case, `a-z0-9_-`, up to 64 characters, with `-2`, `-3` suffixes if taken) and starts as `public`.
- Set name, access type (`public`, `for_sale`, `owned`), price (for `for_sale`) and owner citizenid (for `owned`).
- Draw the dealership zone as a polygon (at least 3 points, up to `Config.maxZonePoints`) with a configurable thickness, or clear it.
- Add vehicles from the `kora_core` shared vehicle registry. Models without a valid shared entry (price at least 1) are dropped on save. Prices are clamped to 1 to `Config.maxPrice`.
- Place display vehicles, spawn points, management points and sale points by aiming at the world. Counts are capped by `Config.maxPlacements`, `Config.maxSpawns` and `Config.maxZones`.
- Switching type to or from `public` resets or fills stock: a public dealership holds 9999 of every vehicle; leaving `public` sets every stock to 0.

## Customers

- Display vehicles are spawned locally (frozen, invincible) at each placement. Using the target option opens the showroom for that display.
- **Swap**: change which vehicle a display shows, for everyone. Limited by `Config.swapDistance` and `Config.swapCooldown`. A "reset" restores the placement's original model. Swaps are in-memory and are cleared when the placements change or the model is no longer sold.
- **Test drive**: spawns the vehicle at `Config.testSpawn` in a private routing bucket (`Config.testBucketBase` plus the server id), with keys and plate `TD` plus the server id. It ends when the player leaves the vehicle, disconnects, or after `Config.testDriveSeconds`. The player is faded back to where they started.
- **Purchase**: charges the player's bank account, takes one stock (owned dealerships), delivers the vehicle at the first free spawn point (no vehicle within `Config.spawnClearance`), gives keys and warps the player in. Any failure refunds. Employees of an owned dealership pay the dealership's `employeeDiscount` percent less.
- **Offer** (owned dealerships only): a two-step form (amount, optional terms up to 500 characters). Limited to `Config.maxPendingOffers` open offers per player. Offers are accepted or denied by staff, or auto-accepted after `Config.autoConfirmOffersDays` days.

## Staff sales

At a sale point, an owner or employee with `sellVehicles` picks a nearby customer (within `Config.nearbyCustomerDistance`), a stocked vehicle and a price within the allowed override range, then sends the offer. The customer sees a confirmation dialog and chooses `cash` or `card` (bank) payment. On success the dealership is credited the price minus commission, the seller receives the commission into their bank account, and the sale is logged (last 500 sales) and counted against the seller's employee record.

## Owner management portal

At a management point the owner, or an employee who has at least one relevant permission, opens the portal. Owners see everything:

- Display placements, spawn points, management points and sale points. New points must lie inside the dealership zone, and the last management point cannot be removed.
- Employees: add a nearby player by server id (up to `Config.maxEmployees`), remove, and set permissions.
- Settings: `maxPriceOverride`, `commission` and `employeeDiscount`, each 0 to 100 percent (defaults 10, 5, 5).
- Funds: deposit from and withdraw to the owner's bank account, up to `Config.maxBalance`. Shows balance, total income and total spent.
- Stock orders: order up to `Config.maxOrderQuantity` of a vehicle at `Config.orderPriceMultiplier` times its list price each, paid from the dealership balance, up to `Config.maxStock` in stock.
- Offers: pending and history lists (up to `Config.offersPageLimit` each) with accept and deny.

Employees only see the pages their permissions allow. See [Permissions](./permissions.md).

## Offer settlement

Accepting an offer takes cash from the offeror (online or offline, cash only), removes one stock, credits the dealership, and writes a garaged `player_vehicles` row (state `Config.offerVehicleState`). Nothing is spawned. If any step fails, earlier steps are reversed and the offer returns to pending (on manual accept) or is denied (on auto-accept). A background loop checks due offers every `Config.autoConfirmCheckSeconds` seconds, 20 at a time.
