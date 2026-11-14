---
title: User interface
sidebar_position: 11
---

# User interface

All screens are `kora_lib` NUI apps.

## Dealership Creator

Opened with `/dealershipcreator`. Views: Dealerships (list and create), Data (name, access, price, owner, delete), Zone (draw polygon or clear), Vehicles (add from the shared catalog and edit prices), Display placements, Spawn points, Management points, Sale points. Placements and points are added by aiming at the world; the app closes while aiming and reopens after saving.

Search the vehicle picker by name when adding models to the dealership. The existing vehicle list is paginated and supports search once it has more than six vehicles. Use **Remove vehicle** on a row and confirm to remove that model, its stock and its display placements.

## Dealership Showroom

Opened from the "browse" target on a display vehicle. Vehicles are grouped by class in a paginated grid with up to two columns. Cards show the full vehicle image and price, and the current vehicle carries an **On display** badge. Each card has purchase, test drive, swap and (owned dealerships only) offer buttons. The header's reset button restores the placement's model.

When a swap or reset reaches the client, any open showroom for that display updates its badge and reset button. Replacing or removing a display vehicle also removes its browse target.

## Sales

The sale-point target is shown only to staff with `sellVehicles`. A compact form picks the customer, vehicle and price (a slider within the override range) and asks for confirmation. The customer gets an input dialog to choose cash or card.

## Dealership Management

The management-point target is shown to everyone on owned dealerships; the server decides who gets in. Pages depend on role: see [Permissions](./permissions.md).

On Orders, search the vehicle picker or browse the paginated inventory. Confirm before submitting a stock order. Pending offers and offer history have separate paginated lists.
