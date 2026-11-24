# 角色表现资源与时装接入

- `levels/01.png`—`80.png` 原样复用本地美食大战老鼠参考资源 `FVM-Official-UI-References/resource/image/level/1.png`—`80.png`；原图包含等级数字，不再叠字。
- 超过 80 级时显示真实等级文字，不将角标钳制为 80，也不限制成长系统。
- `double_loot.png` 复用美食大战老鼠的「物品-双暴卡」。游戏内冒险者徽章使用 `icons/adventurer_badge.png`，白银徽章原图保存在官方参考库。

## 时装素材规格

- `portraits/<id>.png`：完整立绘，960 × 1280，8-bit RGBA PNG，透明背景、3:4 画布。
- 每套时装的头像在装备定义内配置为方形 `AtlasTexture`。`region` 按立绘原图像素取景，以脸部为中心，保留主要发饰、帽子与肩部特征。
- 档案、装备格、任务奖励及商店共用同一张头像。未装配时，档案使用 `portraits/default_farmer_avatar.tres`。
- 角色面板左侧等比展示完整立绘。点选时装时预览该时装，未点选时展示已装配的时装或默认角色。

## 装备接入与上架边界

- 定义资源：`res://resources/adventure/equipment/<id>.tres`，`slot = OUTFIT`，`icon` 绑定头像裁切，`portrait` 绑定完整立绘；默认永久且无数值加成。
- 内容注册：`scripts/adventure/player/equipment_catalog.gd` 的 `DEFINITION_PATHS`。只存路径，按 ID 惰性加载，避免角色越来越多时拖慢启动。
- 注册不等于获取或出售：本次七套新时装只进入装备目录，不自动授予任何存档；已有授予事务可通过装备 ID 发放。
- 商店上架由 `scripts/adventure/shop/shop_catalog.gd` 的 `PRODUCTS` 独立决定。**新增时装不得自行添加到商店**；只有明确确定价格、来源后才允许单独配置。
- 时装切换仍由 `PlayerEquipmentService` 与 `PlayerPortraitArt` 共用，存档只保存稳定的装备 ID，不保存图片路径。

## 本次待上架时装

- `rainy_postman_miro`：雨季邮差·米露
- `midnight_clockmaker_koro`：午夜钟表匠·柯洛
- `unemployed_reaper_moi`：失业的死神·莫伊
- `glass_sea_diver_bubble`：玻璃海潜水员·泡泡
- `snow_train_conductor_eve`：雪国最后的列车长·伊芙
- `don_quixote_lancer`：堂吉诃德（重画冲锋立绘）
- `tiramisu_flower_crown`：提拉米苏
