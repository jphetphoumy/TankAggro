# TankAggro Improvement PRD

## Background
TankAggro monitors player threat and displays aggro status in a collapsible UI. Recent UI revisions introduced issues where section buttons are rendered outside the frame and mob names with counts no longer appear.

## Goals
- Place collapsible section buttons fully inside the add-on frame.
- Restore display of mob and player names in each section.
- Restore counters in section headers.
- Restructure code into multiple Lua files for configuration, UI, and core logic.

## Non-Goals
- Introducing new gameplay mechanics beyond aggro tracking.
- Localisation or extensive configuration options.

## Technical Notes
- Use a shared namespace table between files loaded via the `.toc` file.
- Anchor headers and bodies with both `TOPLEFT` and `TOPRIGHT` points to stay within the frame.
- Keep existing functionality such as sound alerts and colour changes on aggro loss.

## Acceptance Criteria
- UI sections render within the frame with their buttons.
- Names of mobs and group members appear correctly.
- Section headers show accurate counts.
- Add-on loads and functions with code split across multiple files.
