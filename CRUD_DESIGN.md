# Item CRUD Design — Shell-OS Pure

**Status:** Designed, not implemented. Blocked on native compilation (Bend C codegen OOM).
**Date:** 2026-09-20

## Current State

Action 20 ('a' key) appends `It{"New item", sel}`:
- Title is hardcoded "New item" (not user-entered)
- Theme uses `sel` (selection index 0-8) but themes must be 0-3 — BUG
- No edit, no delete

## Design

### EvSt Extension

Add two fields to `EvSt`:
```
EvS{sel, items, tfocus, dirty, quit, writes, vs, entry, entry_mode}
```

- `entry: String` — text buffer for title entry (empty when not entering)
- `entry_mode: U32` — 0=normal, 1=adding, 2=editing (index in `sel`)

All `EvS{...}` constructors must be updated (12 sites in app.bend).

### Key Bindings (normal mode)

- `a` (97): enter add mode → `entry=""`, `entry_mode=1`
- `e` (101): enter edit mode → `entry=current_title`, `entry_mode=2`
- `d` (100): delete selected → remove item at `sel`, save, `dirty=True`
- `0`-`3` (48-51): set theme for new item (when in add mode, before Enter)

### Key Bindings (entry mode)

- Printable ASCII (32-126): append to `entry`
- Backspace (8): remove last char from `entry`
- Enter (13): commit
  - Add mode: append `It{entry, theme}` (theme from 0-3 selection, default 0)
  - Edit mode: replace item at `sel` with `It{entry, old_theme}`
  - Save, `dirty=True`, exit entry mode
- Esc (27): cancel, exit entry mode, discard `entry`

### Theme Validation

Themes must be 0-3. The current `sel` (0-8) is NOT a valid theme.
- Add mode: theme defaults to 0, `0`-`3` keys set it
- Edit mode: preserve existing theme
- `parse_item_theme_num` already validates 0-3 on load

### Persistence

- `save_items` already does atomic write (temp file + rename)
- Set `dirty=True` after add/edit/delete
- The tick loop saves when `dirty` (verify this exists)

### Rendering

- When `entry_mode != 0`, show a text entry bar at bottom
- Display `entry` with cursor
- Show theme indicator for add mode

## Implementation Steps

1. Extend `EvSt` type with `entry: String, entry_mode: U32`
2. Update all 12 `EvS{...}` constructors
3. Add `entry_append`, `entry_backspace` helpers (pure String ops)
4. Add `items_replace_at`, `items_remove_at` helpers
5. Modify `tick_ev_act` to handle entry mode keys
6. Modify `tick_ev_ukey_down` for 'a'/'e'/'d' in normal mode
7. Update render to show entry bar when `entry_mode != 0`
8. Typecheck (`./build.sh check`)
9. Test via JS (native blocked)

## Risks

- EvSt is matched in multiple places; missing a field breaks typecheck
- String append/backspace must be efficient (Bend Strings are linked lists)
- Entry mode must not interfere with PTY terminal input ('t' focuses terminal)

## Verification Plan (when native works)

1. Press 'a', type "Test Item", press '0', press Enter
2. Verify items.txt has `0|Test Item`
3. Restart, verify item loads
4. Select item, press 'e', edit title, Enter
5. Verify change persists
6. Press 'd', verify item removed and file updated
7. Test theme validation: try to set theme 9 (should be rejected or clamped)
