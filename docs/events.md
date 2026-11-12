---
title: Events and callbacks
sidebar_position: 9
---

# Events and callbacks

Client to server communication uses `Kora.callback` (kora_lib). Callbacks return the result, or `false` plus a message. The resource exposes no exports.

## Server callbacks

| Name | Arguments | Access | Description |
| --- | --- | --- | --- |
| `kora_dealership:list` | none | admin | Dealership summaries (id, label, type, price, owner). |
| `kora_dealership:get` | id | admin | Full record. |
| `kora_dealership:create` | label | admin | Creates a public dealership. |
| `kora_dealership:delete` | id | admin | Deletes it (cascades to management and offers). |
| `kora_dealership:save` | id, patch | admin | Applies a sanitized patch. |
| `kora_dealership:swap` | dealer, index, model | near placement | Swap a display model (nil resets). |
| `kora_dealership:testDrive` | dealer, index, model | near placement | Returns the vehicle network id. |
| `kora_dealership:confirmPurchase` | dealer, index, model | near placement | Returns the vehicle network id. |
| `kora_dealership:makeOffer` | dealer, index, model, amount, terms | near placement | Creates a pending offer. |
| `kora_dealership:sales:open` | dealer, index | `sellVehicles`, near sale point | Vehicles, price override and nearby customers. |
| `kora_dealership:sales:confirm` | dealer, index, customer, model, price | `sellVehicles`, near sale point | Runs a staff sale. |
| `kora_dealership:management:openOwnerManagement` | dealer, index | employee, near management point | Portal data. |
| `kora_dealership:management:addEmployee` | dealer, index, serverId | owner | |
| `kora_dealership:management:removeEmployee` | dealer, index, citizenid | owner | |
| `kora_dealership:management:savePermissions` | dealer, index, citizenid, list | owner | |
| `kora_dealership:management:saveSettings` | dealer, index, values | owner | |
| `kora_dealership:management:savePlacement` | dealer, index, patch | owner, or `manageDisplay` for placements | Edits placements, spawns, management and sale points. |
| `kora_dealership:management:depositFunds` | dealer, index, amount | owner | |
| `kora_dealership:management:withdrawFunds` | dealer, index, amount | owner | |
| `kora_dealership:management:orderVehicle` | dealer, index, model, quantity | `orderVehicles` | |
| `kora_dealership:management:getOffers` | dealer, index | `handleOffers` | |
| `kora_dealership:management:resolveOffer` | dealer, index, offerId, decision | `handleOffers` | `accept` or `deny`. |

## Client callback

| Name | Description |
| --- | --- |
| `kora_dealership:sales:confirmPurchase` | Triggered by the server on the customer during a staff sale. Shows a payment dialog and returns `confirmed` and `payment`. |

## Net events

| Event | Direction | Description |
| --- | --- | --- |
| `kora_dealership:server:testDriveEnded` | client to server | Ends the sender's test drive and deletes the vehicle. Ignored when triggered by another resource. |

## Local events

| Event | Side | Description |
| --- | --- | --- |
| `qb-vehicleshop:server:onVehiclePurchased` | server, local | Emitted with citizenid, model, plate. See [Compatibility](./compatibility.md). |

## State bags

Global state published by the server and read by clients: `Dealerships` (all records), `DealershipSwaps` (display swaps), `DealershipStaff` and `DealershipOfferStaff` (citizenids per dealership). `Dealerships` is visible to every client and includes owner citizenids and stock.
