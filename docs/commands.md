---
title: "Commands"
sidebar_position: 4
---


# Commands

One client command, configurable by name. There are no server commands; every admin and portal action is server-validated through callbacks, not ACE-gated commands.

## Client commands

### `/dealershipcreator`

Opens the dealership creator AppShell app. The command itself registers for any player; every list/create/delete/save callback it triggers separately requires the `Config.adminPermission` ace on the server, so a non-admin sees an empty list and every action fails with "Admin permission required."

| Field | Details |
| --- | --- |
| Context | In-game · client command (name from `Config.command`) |
| Arguments | No arguments. |
| Access | Registered for everyone; effectively admin-only because every server callback checks `IsPlayerAceAllowed(src, Config.adminPermission)`. |

**Example**

```text
/dealershipcreator
```

**Result**

The creator app opens listing existing dealerships and a "create new" form.

## Server-side check

The command is registered as unrestricted on the client, so anyone can type it, but every creator callback checks `IsPlayerAceAllowed(src, Config.adminPermission)` on the server (`server/functions.lua:42`). Non-admins receive "Admin permission required." and cannot list or change anything.

There are no other commands. Showroom, sales and management are opened through `kora_target` options.
