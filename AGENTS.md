# kora_dealership agent guide

`kora_dealership` is a Kora dealership resource: an admin creator (`/dealershipcreator`), a customer showroom (swap, test drive, purchase, offers), a staff sales target and an owner management portal, all as `kora_lib` NUI apps. Layout: `fxmanifest.lua`, `config.lua`, `shared/functions.lua` (price helpers), `server/` (`schema.lua`, `functions.lua` shared server helpers, `creator.lua`, `customer.lua`, `sales.lua`, `Management.lua`), `client/` (matching apps, `views.lua`, target zones), `locales/en.lua`, `test/` (offline Lua checks) and `tests/` (kora_qa feature files).

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
