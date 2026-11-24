# 五级生长剂美术规范（已实装）

- 权威图标目录：`res://assets/adventure/ui/items/consumables/growth_agent_lv1.png` ～ `growth_agent_lv5.png`，权威映射：`res://assets/adventure/ui/items/item_icon_map.json`；不设并行资源表。
- 五张独立 PNG，均 256×256、RGBA 透明通道，四周保留留白；通用道具背景沿用 `backgrounds/consumable_backing.png`。
- 以 PVZ 2009 手绘道具风格为准：夸张瓶型、深色轮廓、木塞、玻璃高光、发芽意象；不可叠加 UI 格子边框、等级字样、水印或背景。
- 层次：Lv1 绿色苗芽药瓶；Lv2 绿色系丝带药瓶；Lv3 蓝色晶冠与棱面瓶；Lv4 紫金藤环和紫晶冠；Lv5 翡翠金冠和开花植株。强化效果和适用星级只由研究室规则决定，美术不参与逻辑判定。
- 游戏实际展示以背包/研究室共用 `inventory_item_art.gd` 管线为准；缩至 64×64 时需仍可区分 Lv1–Lv5。
- 旧单级 `growth_agent` 与旧通用图标已撤除，历史存档归并仅在 `AdventureState.from_dict` 读档边界处理。
