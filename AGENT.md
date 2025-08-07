# AGENT.md

## Purpose
You are building a World of Warcraft addon called **TankAggroAlert** that helps tanks track threat/aggro in dungeons, raids, or open world.  
The addon must:
- Show when the tank has aggro on mobs (count + mob names).
- Show when the tank **loses** aggro (count + mob names + who has them now).
- Show which **group members** have aggro on which mobs.
- Indicate when a **group member takes aggro** from the tank (sound alert).
- Allow **collapsible** lists for each category.
- Use a **WoW-native skin** with no overlapping or unreadable text.

---

## Functional Requirements

### 1. Sections
The addon has **three collapsible sections** stacked vertically:
1. **I have aggro** — mobs where the player is tanking (threat status 3).
2. **Lost aggro** — mobs where the player no longer has threat; includes who has them now.
3. **Group aggro** — group member names with the list of mobs they currently have aggro on.

### 2. Threat Tracking
- Use `UnitThreatSituation` to determine threat status.
- Track visible enemy nameplates with `NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED`.
- Only include enemies in combat (`UnitAffectingCombat`).
- For each enemy, determine who holds aggro by scanning the player and all group units.

### 3. Alerts
- If a mob switches from the tank to another group member, **play a sound** once (`SOUNDKIT.RAID_WARNING`).
- Title text color changes based on threat status:
  - **Red** if any lost aggro.
  - **Yellow** if insecure threat.
  - **Default gold** if all secure.

### 4. UI / UX
- Main frame uses `BasicFrameTemplateWithInset`.
- Each section header is a clickable `UIPanelButtonTemplate` with:
  - Text label + count.
  - Arrow indicator (▼ collapsed / ▲ expanded).
- Section bodies:
  - Auto-resize to fit their content.
  - Contain mob/member name lines, padded so no overlap.
  - Have tooltip-style backdrop.
- Collapsing/expanding a section triggers a **layout recalculation** so all sections stack without overlap.
- Padding between sections: **6px**.
- Line height: **14px**.
- Body side padding: **10px**.

### 5. Layout
- No fixed vertical offsets — sections stack dynamically.
- Each section height = header height + visible body height.
- Overall frame height adjusts to fit all visible content.

### 6. Configurability
- Config variable to only show the addon in instances or in all zones.
- Polling interval: **0.2 seconds** to catch edge cases.
- Event-driven updates for nameplate, threat, target, group roster, and zone changes.

---

## Technical Details

### Data Structures
- `tracked` — table of nameplate unit tokens.
- `lastLostTagged` — mob GUID → last known holder (to detect fresh loss).
- `holderLists` — group member name → table of mobs they hold.
- `haveAggro` — list of mobs tank is holding.
- `lostAggro` — list of `mob -> holder`.

### Events
- `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` — track combat state.
- `NAME_PLATE_UNIT_ADDED` / `NAME_PLATE_UNIT_REMOVED` — track visible enemies.
- `UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` — threat change detection.
- `PLAYER_TARGET_CHANGED` — recheck on target change.
- `GROUP_ROSTER_UPDATE` / `ZONE_CHANGED_NEW_AREA` — update instance/group info.

### Functions
- `scanThreat()` — core scan logic, updates lists, triggers sounds, recolors title, updates counts and lines.
- `groupUnitIterator()` — yields unit IDs for all group members.
- `unitHasAggroOnMob(unit, mob)` — wrapper for threat status 3.
- `NewSection(parent, label)` — creates collapsible section with WoW skin.
- `RequestLayout()` — recalculates stacking and frame height.

---

## Acceptance Criteria
1. Expanding lists never overlap other sections.
2. Frame height adjusts to fit all expanded sections.
3. Count in each header matches visible lines in its body.
4. Sound plays once when a group member takes aggro from the tank.
5. Titles and headers visually match WoW’s default UI style.
6. Works both solo and in groups, and can be restricted to instances.
