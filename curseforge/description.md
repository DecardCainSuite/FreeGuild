# Free Guild — CurseForge

## Fields

- **Project name:** Free Guild
- **Summary:** Guild roster and rank tool for guild masters and officers: filters, bulk ranks, rules that promote for you, stats, raid rosters with attendance, guild info and notes.
- **Main category:** Guild
- **Extra categories:** Chat & Communication
- **Logo:** `images/FreeGuild-logo-1024.png` (the 400 px version is there if needed)

## Gallery (title — description)

1. `images/fg_1.png` — **Free Guild** — Guild ranks, sorted out in a few clicks.
2. `images/fg_2.png` — **Your whole roster, at a glance** — Sort, search, filter, select many members at once; To change shows who your rules would move.
3. `images/fg_3.png` — **Your guild in numbers** — Members by class, level band and rank; click a line to open the roster on it.
4. `images/fg_4.png` — **Rules that promote for you** — Level, class, rank, days in the guild, days offline, notes… mapped to ranks.
5. `images/fg_5.png` — **One click per change** — The game allows one rank change per click; Free Guild queues them for you.

---

## Description (paste into the Markdown editor)

# Free Guild

Rank management for guild masters and officers on WoW Forever.

## Roster

- Sortable list: name, level, class, rank, last online, note. Search by name, note or class; filter by rank, level range and online.
- Select many members (click, Shift-click for a range, "Select shown"), choose a rank, queue the changes.
- An orange `*` shows members whose rank does not match your rules. The **To change** filter lists only the members your rules would really move, and queues them all in one click.
- **Invite** sends a group invitation to the selected members who are online (the group becomes a raid when needed).

## Rules

- Up to 8 rules, first match wins. Each rule can combine: **level range**, **class**, **current rank**, **member since** (days), **offline for** (days), and text in the **public or officer note**.
- Rules never touch protected ranks, and only promote unless you allow demotions.
- Reminder at login when someone should get a new rank. Export / import your rules.
- The game does not tell when a member joined: Free Guild remembers the first day it saw each member and counts from there.

## Stats

- Total, online, offline, average level, new members this week, members away for 14-29 and 30+ days, level 60s.
- Members by class, by level band and by rank, with counts, percentages and bars. Click a line to open the roster filtered on it.
- "Online only" switch to count only the members who are online.

## Raids

- Several raid rosters per guild: main or bench, role (tank, healer, DPS), excused for the next raid.
- **Invite roster** invites the main roster members who are online (Shift-click: the bench too).
- **Take attendance** records who is in your group: present, absent, excused or bench. Attendance % and the last 12 raids for each member.

## Applying changes

The game only allows **one rank change per click or key press**. Free Guild queues the changes and sends the next one each time you press **Apply next** or its key binding (Key Bindings › AddOns › Free Guild). No need to refresh the roster between clicks; changes that did not go through are queued again.

## Guild tab

- Message of the day and guild information: read and edit. When the game keeps an edit to its own window, Free Guild uses the game's `/gmotd` command or gives you the text to paste there.
- Public and officer notes of the selected member.
- Last known guild bank money, with the date it was seen.

## Queue & log

The changes waiting to be sent, and the last 300 actions.

## Commands

- `/fg` — open the window
- `/fg next` — show the next queued change

## Free Hub

Free Guild works on its own. With **Free Hub** installed, its options open inside the hub next to the other Free addons, and a single minimap button replaces theirs.

## Notes

- Built for WoW Forever. Rank changes use the game's own `/gpromote` and `/gdemote` commands, one step per click.
- What you can change depends on your guild rank permissions.
- Bug reports and ideas are welcome in the comments.
