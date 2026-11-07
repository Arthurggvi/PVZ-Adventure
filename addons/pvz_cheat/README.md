# PVZ-Adventure Cheat Console · P0

- Tab+O toggles a single cached, non-modal right-side console; Esc closes it. Clicks outside the panel pass through to gameplay. Modules load only when selected; hidden windows intercept no input. No game data changes until an action is clicked.
- Cards: grant registered plants as distinct UIDs, 0–10 stars, up to 32 cards per action.
- Items: grant/consume any ItemRegistry ID; category bulk grants use one save transaction.
- 角色装备：通过正式角色事务授予目录装备；在地图上设置等级时按成长曲线同步累计经验和任务门槛。
- Coins: add/subtract/set the one authoritative coin balance, including setting 0.
- Stages: unlock to stage, mark a clear without loot, jump to an entered stage after setting its prerequisites. Normal victory settlement still requires all boss/events completed.
- Battle: spawn a registered zombie at tier 1–5 in a compatible lane or once per lane. One-click clear settles the active stage or phase without crediting skipped Boss defeats.
- Saves: snapshot and restore the current profile's GlobalSaveGame.json; no restore during an active battle.
- All state-changing operations save through SaveService; on failed save, restore prior in-memory state.
- Only scripts/adventure/ui/cheat_loader.gd is a permanent base-game reference. Development loads addons/pvz_cheat/ directly; release needs optional PVZ_Cheat.pck beside the executable. Exporting and release QA of that PCK are not yet completed.
- P1 not implemented: sun/cooldown toggles, wave jump, boss phase overrides, weather and speed presets.
