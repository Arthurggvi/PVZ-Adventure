# PVZ-Adventure Cheat Console · P0

- Tab+O toggles a single cached, non-modal right-side console; Esc closes it. Clicks outside the panel pass through to gameplay. Modules load only when selected; hidden windows intercept no input. No game data changes until an action is clicked.
- Cards: grant registered plants as distinct UIDs, 1–20 stars, up to 32 cards per action.
- Items: grant/consume any ItemRegistry ID; category bulk grants use one save transaction.
- Coins: add/subtract/set the one authoritative coin balance, including setting 0.
- Stages: unlock to stage, mark a clear without loot, jump to an entered stage after setting its prerequisites. Normal victory settlement still requires all boss/events completed.
- Saves: snapshot and restore the current profile's GlobalSaveGame.json; no restore during an active battle.
- All state-changing operations save through SaveService; on failed save, restore prior in-memory state.
- Only scripts/adventure/ui/cheat_loader.gd is a permanent base-game reference. Development loads addons/pvz_cheat/ directly; release needs optional PVZ_Cheat.pck beside the executable. Exporting and release QA of that PCK are not yet completed.
- P1 not implemented: sun/cooldown toggles, wave jump, enemy spawning, boss phase overrides, weather and speed presets.
