# qbdealership

`qbdealership` is a server-authoritative vehicle dealership for qbcore2.

Its catalogue never duplicates vehicle facts. Add `{ vehicle = 'model' }` to
a dealership's `Config.dealerships.<id>.vehicles` list and the resource
resolves its display name, brand and default price from qbcore's live shared
`vehicles` registry (seeded in `qbcore/shared/vehicles.lua`). Add `price` to a
row only when that dealership needs an override, for example
`{ vehicle = 'kuruma', price = 90000 }`.

Purchases are revalidated on the server: the player must be at the configured
location and routing bucket; the requested model must be in that dealership's
allow-list and still be a positive-priced shared vehicle. The server charges
the shared price through qbcore's money funnel, creates the civilian ownership
row through qbcore's garage API, and refunds on a failed write. The purchased
vehicle is then available at `qbgarages`.

Start after `qblib` and `qbcore`:

```cfg
ensure qbdealership
```

Run the deterministic smoke suite with `test/run.sh`.
