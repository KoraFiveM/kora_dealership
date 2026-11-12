# kora_dealership agent guide

`kora_dealership` is a Kora dealership resource: an admin creator (`/dealershipcreator`), a customer showroom (swap, test drive, purchase, offers), a staff sales target and an owner management portal, all as `kora_lib` NUI apps. Layout: `fxmanifest.lua`, `config.lua`, `shared/functions.lua` (price helpers), `server/` (`schema.lua`, `functions.lua` shared server helpers, `creator.lua`, `customer.lua`, `sales.lua`, `Management.lua`), `client/` (matching apps, `views.lua`, target zones), `locales/en.lua`, `test/` (offline Lua checks) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first (it maps every page). Layout: `index.md` (hub), `installation.md` (setup, requirements, tests), `how-to-use.md` (admin, customer, staff and owner walkthrough), `commands.md`, and topic pages (`features`, `configuration`, `permissions`, `events`, `database`, `ui`, `compatibility`, `troubleshooting`). There is no `api/` section: the resource exposes no exports. Update the page that owns the topic.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.

Copyright © 2026 Kora Framework (new contribution guidance).
