---
title: User interface
sidebar_position: 11
---

# User interface

All screens are `kora_lib` NUI apps.

## Dealership Creator

Opened with `/dealershipcreator`. Views: Dealerships (list and create), Data (name, access, price, owner, delete), Zone (draw polygon or clear), Vehicles (add from the shared catalog), Display placements, Spawn points, Management points, Sale points. Placements and points are added by aiming at the world; the app closes while aiming and reopens after saving.

## Dealership Showroom

Opened from the "browse" target on a display vehicle. Vehicles are grouped by class. Each card has swap, test drive, purchase and (owned dealerships only) offer buttons, plus a reset button to restore the placement's model.

## Sales

The sale-point target is shown only to staff with `sellVehicles`. A form picks the customer, vehicle and price (a slider within the override range) and asks for confirmation. The customer gets an input dialog to choose cash or card.

## Dealership Management

The management-point target is shown to everyone on owned dealerships; the server decides who gets in. Pages depend on role: see [Permissions](./permissions.md).
