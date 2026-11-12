---
title: Permissions
sidebar_position: 8
---

# Permissions

## Admin ACE

Creator callbacks (`list`, `get`, `create`, `delete`, `save`) require the ACE in `Config.adminPermission` (default `admin`):

```cfg
add_ace group.admin admin allow
```

## Roles on an owned dealership

| Role | How determined | Can do |
| --- | --- | --- |
| Owner | The `owner` citizenid of the dealership | Everything: all portal pages, staff sales, discount price, all permissions implicitly. |
| Employee | Listed in the dealership's employees | Employee discount on purchases, plus portal pages granted by permissions. |
| Customer | Anyone else | Browse, swap, test drive, buy at list price, make offers. |

## Employee permissions

Granted by the owner per employee. Values come from `Config.employeePermissions`:

| Value | Label | Grants |
| --- | --- | --- |
| `sellVehicles` | Sell vehicles | Sale-point target and staff sales. |
| `handleOffers` | Handle offers | Management Offers page: accept and deny. |
| `orderVehicles` | Order vehicles | Management Orders page. |
| `manageDisplay` | Manage display placements | Add and remove display placements (not spawns or zones). |

Only the owner can add or remove employees, set permissions, change settings, move funds, and edit spawn points, management points and sale points. A new employee starts with no permissions. Added employees must be within `Config.nearbyCustomerDistance` of the owner.

The client mirrors staff lists from the `DealershipStaff` and `DealershipOfferStaff` state bags only to decide whether to show target options; the server re-checks every action.
