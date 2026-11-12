---
title: Commands
sidebar_position: 4
---

# Commands

| Command | Who | Description |
| --- | --- | --- |
| `/dealershipcreator` | Admins | Opens the creator app. The name comes from `Config.command`. |

The command is registered as unrestricted on the client, so anyone can type it, but every creator callback checks `IsPlayerAceAllowed(src, Config.adminPermission)` on the server. Non-admins receive "Admin permission required." and cannot list or change anything.

There are no other commands. Showroom, sales and management are opened through `kora_target` options.
