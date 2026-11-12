---
title: Compatibility
sidebar_position: 12
---

# Compatibility

`fxmanifest.lua` declares `provide 'qb-vehicleshop'`, so resources that depend on `qb-vehicleshop` are satisfied.

After every confirmed purchase the server triggers the local server event:

```lua
TriggerEvent('qb-vehicleshop:server:onVehiclePurchased', citizenid, model, plate)
```

It fires for public purchases, staff sales and accepted offers. Stock `qb-vehicleshop` features (transfer vehicle, spawn vehicle, showroom events) are not provided. Purchased vehicles are written to `player_vehicles` with the standard columns shown in [Database](./database.md).
