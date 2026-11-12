---
title: Database
sidebar_position: 10
---

# Database

Tables are created and kept current by `kora_sql` (`ensureTables`) when the resource starts. No manual import is required. All use `utf8mb4_unicode_ci`.

## kora_dealerships

| Column | Type | Notes |
| --- | --- | --- |
| `id` | varchar(64) | Primary key. |
| `label` | varchar(128) | Display name. |
| `type` | enum | `public`, `for_sale`, `owned`. |
| `price` | int unsigned, null | For `for_sale`. |
| `owner` | varchar(50), null | Owner citizenid. |
| `zone` | longtext JSON | Polygon points and thickness. |
| `vehicles` | longtext JSON | Entries with model, name, price, stock. |
| `placements` | longtext JSON | Display vehicles (model and coords). |
| `spawns` | longtext JSON | Delivery points. |
| `management_zones` | longtext JSON | Management points. |
| `sale_zones` | longtext JSON | Sale points. |
| `created_at`, `updated_at` | timestamp | |

With `Config.UsePDM` the table is seeded with a `pdm` row.

## kora_dealership_management

One row per owned dealership, created lazily on first access. Foreign key to `kora_dealerships.id` with cascade.

| Column | Type | Notes |
| --- | --- | --- |
| `dealership_id` | varchar(64) | Primary key. |
| `current_balance` | int | Funds. |
| `income`, `spent` | int unsigned | Running totals. |
| `sales` | longtext JSON | Sale log, last 500. |
| `employees` | longtext JSON | citizenid, name, sales, income. |
| `employee_permissions` | longtext JSON | citizenid to permission list. |
| `settings` | longtext JSON | `maxPriceOverride`, `commission`, `employeeDiscount`. |

## kora_dealership_offers

| Column | Type | Notes |
| --- | --- | --- |
| `id` | int unsigned | Auto increment key. |
| `dealership_id` | varchar(64) | Foreign key with cascade; indexed. |
| `model` | varchar(64) | |
| `offer_price` | int unsigned | |
| `offer_text` | varchar(500) | Customer terms. |
| `auto_accept_at` | datetime, null | When the offer is auto-accepted. |
| `status` | enum | `pending`, `accepted`, `denied`. |
| `offeror` | varchar(50) | Customer citizenid. |
| `acceptor` | varchar(50), null | Staff citizenid, or `system` for auto decisions. |

Indexes: `idx_offers_dealership`, `idx_offers_offeror`, `idx_offers_pending_auto_accept`.

## Tables from other resources

- `players`: read (`charinfo`) for names and updated (`money.cash`) to charge or pay an offline offeror.
- `player_vehicles`: plate uniqueness lookup and inserts for every purchased vehicle (plate, vehicle, citizenid, state, fuel 100, engine and body health 1000, no finance).
