# Free Guild — CurseForge

## Fields

- **Project name:** Free Guild
- **Summary:** Guild roster and rank tool for guild masters and officers: filters, bulk ranks, rules that promote for you, guild info and notes.
- **Main category:** Guild
- **Extra categories:** Chat & Communication
- **Logo:** `images/FreeGuild-logo-1024.png` (the 400 px version is there if needed)

## Gallery (title — description)

1. `images/fg_1.png` — **Free Guild** — Guild ranks, sorted out in a few clicks.
2. `images/fg_2.png` — **Your whole roster, at a glance** — Sort, search, filter, select many members at once.
3. `images/fg_3.png` — **Rules that promote for you** — Level, class, seniority, last online, notes… mapped to ranks.
4. `images/fg_4.png` — **One click per change** — The game allows one rank change per click; Free Guild queues them for you.

---

## Description (paste into the Markdown editor)

# Free Guild

Rank management for guild masters and officers on WoW Forever.

## Roster

- Sortable list: name, level, class, rank, last online, note. Search by name, note or class; filter by rank, level range and online.
- Select many members (click, Shift-click for a range, "Select shown"), choose a rank, queue the changes.
- An orange `*` shows members whose rank does not match your rules.

## Rules

- Up to 8 rules, first match wins. Each rule can combine: **level range**, **class**, **current rank**, **member since** (days), **offline for** (days), and text in the **public or officer note**.
- Protected ranks are never touched. Rules only promote unless you allow demotions.
- Reminder at login when someone should get a new rank. Export / import your rules.
- The game does not tell when a member joined: Free Guild remembers the first day it saw each member and counts from there.

## Applying changes

The game only allows **one rank change per click or key press**. Free Guild queues the changes and sends the next one each time you press **Apply next** or its key binding (Key Bindings › AddOns › Free Guild). No need to refresh the roster between clicks; changes that did not go through are queued again.

## Guild tab

- Message of the day and guild information: read and edit.
- Public and officer notes of the selected member.
- Last known guild bank money, with the date it was seen.

## Commands

- `/fg` — open the window
- `/fg next` — show the next queued change

## Free Hub

Free Guild works on its own. With **Free Hub** installed, its options open inside the hub next to the other Free addons, and a single minimap button replaces theirs.

## Notes

- Built for WoW Forever. Rank changes use the game's own `/gpromote` and `/gdemote` commands, one step per click.
- What you can change depends on your guild rank permissions.
- Bug reports and ideas are welcome in the comments.
