# Changelog

## v1.11.3 (2026-10-23)

### Fixed
- A macro like `/cast !Stealth` was saved as a spell called "!Stealth", so its button stayed empty on a new
  character. A "!" in front (it keeps Stealth, an aura or a stance from toggling off) now keeps it a macro. A plan
  saved before puts the macro back on that button when applied.

## v1.11.2 (2026-10-23)

### Fixed
- Apply from the window could freeze the game for a moment when it changed many keybindings: the window redrew
  itself once for every key. It now redraws once.
- Export and Export all took noticeably long with several plans. They use a faster compression setting now (the text
  is a little longer; Import reads both).
- After the Import window had been open, Export showed Import's summary and its "macros that run code" checkbox under
  the text. It shows the character count again.

## v1.11.1 (2026-10-21)

### Fixed
- A button BarPlan couldn't read when a plan was saved was left out of the plan, so Apply cleared it and put
  nothing back. Such a button is now kept in the plan as "keep as it is", and Apply leaves it alone.

### New
- `/barplan debug [from-to]` (default 1-12) lists what BarPlan sees on those buttons and what the plan has there,
  for bug reports.

## v1.11.0 (2026-10-21)

### New
- The plan list in the window shows the plans of every class (yours first, each with its class), so you can
  export, delete or choose the plan offered to new characters of any class from any character. Apply stays for
  plans of your own class. `/barplan export <name>` finds a plan of another class by its name too.
- Export all (in the window, or `/barplan exportall`): every plan of every class in one text. Import adds them
  all back.
- Import no longer replaces a plan by default: a name you already have gets a number ("Paladin (2)"). The window
  says for each plan what will happen; for a single plan you can still type an existing name to replace it.
- Macros that run code are still left out of an imported plan by default; a checkbox in the import window (shown
  when the text has such macros, off each time) imports them too, at your own discretion.

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
