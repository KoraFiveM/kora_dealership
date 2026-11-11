# kora_dealership

Dealerships for QBCore: an admin creator, a customer showroom (display swaps, test drives,
purchases, offers), a sales target for staff, and an owner management portal (employees,
permissions, funds, stock orders, offers, display editing).

Run `/dealershipcreator` (ace `Config.adminPermission`, default `admin`) to open the creator.

## Setup

1. Nothing to import: on start kora_sql creates `kora_dealerships`, `kora_dealership_management`
   and `kora_dealership_offers` and adds anything missing to existing ones. With `Config.UsePDM`
   it also seeds a public `pdm` dealership if it is missing.
2. Make sure the ace named in `Config.adminPermission` is granted to your admins, e.g.
   `add_ace group.admin admin allow`.
3. Dependencies: `kora_lib`, `kora_sql`, `kora_core`, `kora_vehiclekeys`, `kora_target`.

## Dealership types

- **public**: everyone can buy, stock is unlimited.
- **for_sale**: not yet owned.
- **owned**: has an owner, employees, a balance, finite stock, sale/management zones and offers.

## Tables

- `kora_dealerships`: label, type, price, owner and the zone/vehicles/placements/spawns/zones as JSON.
- `kora_dealership_management`: balance, income, spent, sales log, employees, permissions, settings.
- `kora_dealership_offers`: customer offers on owned dealerships; accepted, denied, or auto-accepted
  after `Config.autoConfirmOffersDays`.

Limits and tunables (caps, cooldowns, test drive length, distances) are in `config.lua`.

## QBCore compatibility

The resource provides `qb-vehicleshop`. After every confirmed purchase (public purchase, employee sale, accepted offer) it emits the server-local event `qb-vehicleshop:server:onVehiclePurchased(citizenid, model, plate)`. Stock `transfervehicle`, `spawnvehicle` and showroom events are not provided.
