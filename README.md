# qbdealership

Dealerships for QBCore: an admin creator, a customer showroom (display swaps, test drives,
purchases, offers), a sales target for staff, and an owner management portal (employees,
permissions, funds, stock orders, offers, display editing).

Run `/dealershipcreator` (ace `Config.adminPermission`, default `admin`) to open the creator.

## Setup

1. Import `sql/dealers.sql` (creates `qbdealerships`, `qbdealership_management`,
   `qbdealership_offers` and seeds a public `pdm` dealership; safe to re-run).
2. Make sure the ace named in `Config.adminPermission` is granted to your admins, e.g.
   `add_ace group.admin admin allow`.
3. Dependencies: `qblib`, `qbsql`, `qbcore`, `qbvehiclekeys`, `qbtarget`.

## Dealership types

- **public**: everyone can buy, stock is unlimited.
- **for_sale**: not yet owned.
- **owned**: has an owner, employees, a balance, finite stock, sale/management zones and offers.

## Tables

- `qbdealerships`: label, type, price, owner and the zone/vehicles/placements/spawns/zones as JSON.
- `qbdealership_management`: balance, income, spent, sales log, employees, permissions, settings.
- `qbdealership_offers`: customer offers on owned dealerships; accepted, denied, or auto-accepted
  after `Config.autoConfirmOffersDays`.

Limits and tunables (caps, cooldowns, test drive length, distances) are in `config.lua`.
