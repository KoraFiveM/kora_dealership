# qbdealership (creator only)

Everything except the dealership creator was removed: no showroom, no
stock/offers, no purchase flow. This resource only builds and stores
dealership definitions -- another resource reads `qbdealerships` to actually
use them.

Run `/dealershipcreator` (admin permission required) to open the AppShell:

- **Dealerships** -- list existing ones, or create a new one by name.
- **Data** -- name, Public vs For Sale (+ price), delete.
- **Zone** -- `QB.zones.startCreator('poly')` to draw the dealership's
  polygon; stored as `{points, thickness}`.
- **Vehicles** -- search `exports['qb-core']:GetShared('Vehicles')` by name
  and add to this dealership's list.
- **Placements** -- pick one of the dealership's vehicles, then aim and
  confirm with `QB.raycast.getCoords` to place a display model.
- **Spawns** -- `QB.raycast.getCoords` with a fixed `asbo` preview; add as
  many as you like.

One table, `qbdealerships` (`sql/001_dealerships.sql`): label, type, price,
and the zone/vehicles/placements/spawns each as a JSON column.

One correction from the original spec: qblib's actual parameter is
`QB.raycast.getCoords({ type = 'object', object = modelName })` -- the key is
`object`, not `model`. Checked straight against `modules/raycast/client.lua`.
