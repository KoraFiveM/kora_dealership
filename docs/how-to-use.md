---
title: "How to use"
sidebar_position: 3
---


# How to use

Three different people use this resource: an admin building the dealership, a customer buying or test-driving, and (for an owned dealership) the owner/employees selling and managing stock. All of it runs through Kora Lib's AppShell NUI apps and Kora Target interaction points; none of it is a traditional qb-menu.

## Building a dealership (admin)

1. **Open the creator** — Run `/dealershipcreator` (or the configured `Config.command`). The AppShell app `kora_dealership:creator` opens, listing existing dealerships and a form to create a new one.

2. **Set the basics** — Select a dealership to edit its Data page: label, access type (`public`/`for_sale`/`owned`), a price (only used for `for_sale`) and an owner citizen id (only used for `owned`, and not validated against a real character — see "Unclear" below).

3. **Draw the zone** — On the Zone page, "Draw zone" calls `Kora.zones.startCreator('poly')` (the shared Kora Lib polygon drawing tool) and saves the resulting points/thickness. Every placement, spawn point, management zone and sale zone added afterwards must fall inside this polygon (new points only — points that already existed are grandfathered in in case the zone shrinks).

4. **Pick vehicles and prices** — On the Vehicles page, add a model from the shared vehicle catalogue (`exports.kora_core:allShared('vehicles')`); its price defaults to the catalogue price and can be overridden per dealership (clamped to `Config.maxPrice`, 5,000,000 by default).

5. **Place display cars, spawns and the two target zones** — On Placements, Spawns, Management and Sales pages, clicking "Add" closes the app and starts an aim-based placement tool (`Kora.raycast.getCoords`): aim at a point in the world (or at an object of the chosen model, for a placement) and the coordinate is saved to the dealership on the server.

- Limits: `Config.maxPlacements` (50), `Config.maxSpawns` (20), `Config.maxZones` (10, applies separately to management and sale zones), `Config.maxZonePoints` (32 points per polygon).
- A dealership keeps at least one management zone once it has any: the portal you use to manage it is reached through that same zone, so the last one cannot be deleted from the Management portal (it can still be deleted from the admin creator, which has no such guard).

## Customer: showroom, test drive, purchase, offers

Each placed display vehicle is a real spawned entity with a Kora Target interaction ("Browse vehicles"). Selecting it opens the `kora_dealership:showroom` AppShell app, one tab per vehicle class (using the GTA vehicle class table and `Config.categories`).

- **Swap display** — "Swap" changes what that one placement displays for every player (no purchase, no save to the database row: it is server-side session state in `Swaps`, published through `GlobalState.DealershipSwaps`). "Reset" puts the originally-placed model back. Rate-limited to `Config.swapCooldown` (1000 ms) and must be within `Config.swapDistance` (6.0 m) of the placement.
- **Test drive** — spawns a temporary vehicle at `Config.testSpawn`, gives keys through kora_vehiclekeys, and puts the player (and the vehicle) in a private routing bucket (`Config.testBucketBase + source`) so other players never see it. Ends when the player gets out and stays out (`Kora.cache.onChange('vehicle', ...)`), or after `Config.testDriveSeconds` (120 s) server-side regardless. Must be within `Config.testDriveDistance` (5.0 m) of the placement; rate-limited to `Config.rateLimits.testDrive` (3000 ms).
- **Purchase** — takes the full price from the player's bank account in one call (`exports.kora_core:removeMoney(src, 'bank', price)`); there is no financing, down payment or loan path anywhere in this resource. An owned dealership's employees get `Config.employeeDiscount` (a per-dealership setting, default 5%) off. On success the vehicle is spawned at a free spawn point (first one with no other vehicle within `Config.spawnClearance`, 3.0 m), keys are given, the player is warped in, and a `player_vehicles` row is inserted with `state = 'out'`. A failure at any step (stock, dealership credit, vehicle delivery) refunds the exact amount taken and reverses any partial stock/credit change. Rate-limited to `Config.rateLimits.purchase` (2000 ms).
- **Make an offer** — only on `owned` dealerships. A two-step dialog (amount, then free-text terms) submits a `pending` row to `kora_dealership_offers`. A player may have at most `Config.maxPendingOffers` (5) pending offers at once. `Config.autoConfirmOffersDays` (14) sets an `auto_accept_at` timestamp; a server loop (`autoAcceptLoop`, every `Config.autoConfirmCheckSeconds` = 10 min) auto-accepts any offer whose deadline has passed, or denies it if it can no longer be completed (offeror can't pay, vehicle no longer sold/out of stock).

## Employee-assisted sale (owned dealerships)

Staff with the `sellVehicles` permission (owners always qualify) can interact with a dealership's sale-zone targets to open the `kora_dealership:sales` app.

1. **Pick a customer and vehicle** — Only vehicles with stock > 0 are offered. Customers are other online players within `Config.nearbyCustomerDistance` (8.0 m) of the seller.

2. **Set a price** — The slider is bounded by `DealershipOrders.priceBounds(listedPrice, settings.maxPriceOverride)` — the listed price plus/minus `maxPriceOverride` percent (a per-dealership setting, default 10%), clamped to `[1, Config.maxPrice]`.

3. **Customer confirms** — The server calls back to the customer's client (`kora_dealership:sales:confirmPurchase`) with a dialog to accept/decline and choose cash or card. Declining or closing it fails the sale.

4. **Server re-validates and settles** — After the customer answers, the server re-checks the seller's authorization, the customer's distance, vehicle availability and the price bounds (because time has passed), then removes the money from the chosen account (`cash` or `bank`), decrements stock, delivers the vehicle and records the sale.

- A sale's net amount minus commission is credited to the dealership balance; the commission (a per-dealership setting, default 5%) is paid to the selling employee's bank account directly.
- A seller is locked for `Config.saleConfirmTimeout` (60 s) once a sale prompt is sent to a customer, to prevent sending two sale prompts in parallel.

## Owner management portal (owned dealerships)

A management-zone target opens `kora_dealership:management`. The owner sees every page; an employee only sees the pages their granted permissions cover (`manageDisplay`, `orderVehicles`, `sellVehicles`' effect is in the sales target not this portal, `handleOffers`).

- **Orders** (`orderVehicles`) — buys stock at `DealershipOrders.unitCost(listedPrice)` = `listedPrice * Config.orderPriceMultiplier` (0.7) per unit, up to `Config.maxOrderQuantity` (10) per order and `Config.maxStock` (100) total per model, paid from the dealership balance.
- **Employees** (owner only) — add by nearby server id (within `Config.nearbyCustomerDistance`), up to `Config.maxEmployees` (20); remove by citizen id. The owner cannot be added as an employee of their own dealership.
- **Permissions** (owner only) — toggle each employee's permissions from the fixed list in `Config.employeePermissions` (`sellVehicles`, `handleOffers`, `orderVehicles`, `manageDisplay`).
- **Funds** (owner only) — deposit from or withdraw to the owner's own bank account. The balance is capped at `Config.maxBalance` (2,000,000,000 — the DB column is `int`).
- **Settings** (owner only) — `maxPriceOverride`, `commission`, `employeeDiscount`, each a whole percentage clamped to `[0, 100]`.
- **Placements/Spawns/Zones editing** (`manageDisplay` for placements; the other point lists are owner-only through this portal) — add or remove points the same way the admin creator does, still constrained to the dealership's drawn zone.
- **Offers** (`handleOffers`) — list pending and historical offers (`Config.offersPageLimit`, 50 shown per list) and accept or deny a pending one. Accepting takes cash from the offeror (works even if they are offline) and delivers the vehicle to their garage (`player_vehicles.state = Config.offerVehicleState`, default `garaged`) rather than spawning it.

## QBCore / qb-vehicleshop compatibility

The manifest provides `qb-vehicleshop` (a legacy resource name) so other resources' `dependency` checks still resolve. After every confirmed purchase — public showroom purchase, employee-assisted sale, or an accepted offer — the server-local event `qb-vehicleshop:server:onVehiclePurchased(citizenid, model, plate)` is raised (via `TriggerEvent`, not `TriggerClientEvent`: listeners must be server-side). Stock `transfervehicle`, `spawnvehicle` and showroom NUI events from the original qb-vehicleshop are not provided — a script depending on those specifically will not work.

## Unclear from source

- Setting a dealership's `owner` in the admin creator's Data page accepts any text up to 50 characters; it is never checked against a real `players.citizenid` row. An invalid owner id silently makes the dealership effectively unmanageable (no one can pass the owner check) until corrected.
- There is no server flow that lets a player purchase a `for_sale` dealership itself (become its owner by paying `price`); the price field exists and is stored, but no command/callback in this resource reads it to transfer ownership.
- `Config.adminPermission` check uses `IsPlayerAceAllowed`, so the console (source 0) is not automatically treated as allowed the way some other Kora resources special-case source 0 for admin commands — not explicitly re-verified against FXServer's own behavior for the console pseudo-player.
