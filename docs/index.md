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

Dependencies and setup steps are on the [Installation](./installation.md) page.

## Documentation map

- [Installation](./installation.md) - setup steps, dealership types, requirements, offline tests
- [How to use](./how-to-use.md) - walkthrough for admins, customers, staff and owners
- [Features](./features.md) - what players, staff, owners and admins can do
- [Configuration](./configuration.md) - every `Config` option
- [Commands](./commands.md) - the creator command and its access checks
- [Permissions](./permissions.md) - admin ACE, owner, and employee permissions
- [Events and callbacks](./events.md) - server callbacks, net events, state bags
- [Database](./database.md) - tables, columns and external tables used
- [User interface](./ui.md) - creator, showroom, sales, and management apps
- [Compatibility](./compatibility.md) - `qb-vehicleshop` provide and purchase event
- [Troubleshooting](./troubleshooting.md) - caveats and common problems

This resource exposes no exports.
