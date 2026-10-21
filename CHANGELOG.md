# Changelog

## v1.10.1 (2026-10-21)

### Fixed
- The reload question after Apply could sit behind or overlap other windows. It now stays in front of everything,
  in the middle of the screen.

## v1.10.0 (2026-10-20)

### New
- Share a plan as a text string: Export in the window (or `/barplan export [name]`) shows it to copy; Import
  (`/barplan import`) adds a plan from one to its class, on any character or account. Macros that run code
  (`/run`, `/script`, `/console`, `/click` ...) are left out of an imported plan.

## v1.9.1 (2026-10-20)

### Fixed
- A spell you learn was left where the game put it, on the first empty button: on a button the plan keeps for a
  spell you haven't learned yet (which then never went there), or on one the plan keeps empty. A spell the game
  places as you learn it now goes off any button the plan doesn't have it on, so the plan's buttons stay free.

## v1.9.0 (2026-10-19)

### New
- Edit Mode layout: a plan keeps the Blizzard Edit Mode layout its character uses. Applying it adds the layout
  (replacing an older one of the same name), makes it the new character's and offers a reload to set it up.
  Its own On/Off switch in the window, `/barplan editmode on|off`. Save a plan again to add its layout.
- The reload question after Apply covers addons and the layout together.

## v1.8.0 (2026-10-19)

### New
- A plan saved on a character using the account-wide keybindings now keeps those keys too. Applying it sets the
  account-wide keys to the plan's, so a new account or a fresh WoW folder gets your keys as well (before, it only
  switched the character to the account-wide keys, whatever they were). Save such a plan again to add its keys.

## v1.7.0 (2026-10-19)

First release on CurseForge.

### New
- A macro that only casts one spell (`#showtooltip X` / `/cast X`) is saved in a plan as that spell. Keep such
  placeholders on the character you save from (for spells it can't learn yet): new characters get the plain
  spell on that button when they learn it, and no macro.

## v1.6.1 (2026-10-19)

### New
- "Character specific keybindings" switch in the window: shows whether the character you're on has its own
  keybindings and turns them on (a copy of your current keys) or off (back to the account-wide keys).

## v1.6.0 (2026-10-19)

### New
- Keybindings: a plan saved on a character with its own keybindings keeps every key and what it does (macro,
  spell and addon button keys included). Applying it gives the new character those keys as its own set; a plan
  saved with the account-wide keys gives it the account-wide keys.
- `/barplan keys on|off`.

## v1.5.2 (2026-10-19)

### Fixed
- Which addons are on was read wrongly when several of your characters share a name (deleted and made again):
  every addon counted as on, so a plan's addon list didn't switch anything. Addons are now read and switched
  for exactly the character you're on.

## v1.5.1 (2026-10-19)

### New
- Addons, chat tabs (and from v1.6 keybindings) each have an On/Off switch in the window, on by default:
  whether Apply sets them up too. `/barplan addons on|off`, `/barplan chat on|off`.

## v1.5.0 (2026-10-19)

### New
- Chat tabs: a plan keeps each chat tab's name, message types, channels, font size, colour and place in the
  dock. Applying it sets General and Combat Log up the same, opens the tabs you added and closes added tabs the
  plan doesn't have.

## v1.4.0 (2026-10-19)

### New
- Addons: a plan keeps which addons were on. Applying it switches this character's addons to match and offers
  a reload.

## v1.3.1 and earlier

- Save a character's action bars as a named plan of its class; a new character of that class is offered the
  plan at its first login. Spells you haven't learned yet go onto their buttons when you learn them, a new rank
  replaces the old one, and macros of the plan are made when missing. Minimap button and `/barplan` window.
