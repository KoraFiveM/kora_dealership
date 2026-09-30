# qbdealership

`qbdealership` is a database-backed dealership creator, customer showroom and
management suite built entirely on qblib's shared AppShell.

## What it provides

- NPC-operated dealerships with unlimited showroom stock.
- Player-operated dealerships tied to a QB Core job and business account.
- QB Core shared vehicle names, brands and base prices as the authoritative
  catalogue; per-dealership sale prices are stored only as overrides.
- Wholesale stock, physical display vehicles, test drives and purchase spawns.
- Offers from customers to buy dealership vehicles or sell their own vehicles.
- Cash-only offers within server pricing bounds that automatically settle after
  `Config.AutoSellTime` when enabled globally and on the dealership.
- Cash plus free-form consideration (for example meals or services). Any offer
  with non-cash terms always requires a manager and is never auto-accepted.
- Manager accept, decline and counteroffer flows, plus customer acceptance of a
  counteroffer.
- In-game dealership, zone, inventory, display and spawn-point creation.

## Dependencies

Start the resource after `qblib`, `qbsql`, `qbcore`, `qbtarget`, `qbbanking`
and `qbbossmenu`. The latter two are required for player-owned dealership
accounts; NPC dealerships do not use a society balance.

```cfg
ensure qbdealership
```

Startup applies the packaged SQL migrations through qbsql and imports any
missing definitions from `Config.dealerships`. Use `/dealership` to choose a
dealership. Administrators also see Creator; job bosses see Management.

## Important configuration

```lua
Config.AutoSellTime = 15 * 60
Config.AutoAccept.enabled = true
Config.WholesalePrice = 0.70
```

Each dealership also has its own `autoAccept` switch. Both switches must be on
for timed cash offers. Automatic settlement waits until the customer is online
and retains server authority over identity, ownership, stock, pricing, money
and vehicle delivery.

Automatic purchase offers must meet or exceed the current dealership sale price.
Automatic trade-in payments cannot exceed the QB Core shared base price or a
lower dealership sale override. These bounds are checked when submitting an
offer and again before automatic settlement. Offers outside them stay pending
for manual review, including when prices change while an offer waits. Authorized
manager approvals and customer acceptance of negotiated counteroffers retain
their agreed amounts.

Offer settlement saves a durable claim before payment or delivery. A normal
operation refusal releases the claim for retry. An unexpected effect error or
failed completion write retains it across restarts and logs the offer for
administrator review; automatic retries, expiry and manager actions cannot
replay a claimed offer. Migration 003 adds this flag without changing the
existing offer statuses.

The shared qblib placement editor is used for display/test-drive/purchase
coordinates. Its instructional HUD owns rotation and vertical movement; placed
showroom and test-drive vehicles are grounded with
`SetVehicleOnGroundProperly`.

Run the deterministic smoke suite with `test/run.sh`.
