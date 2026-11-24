# 战场种植空间｜配置与扩展入口

## 权威链

`AdventureStageOverride.board_definition` → `AdventureBattleEnvironment.board_definition` → `ResourceLevelData.board_definition` → `MainGameManager._enter_tree()` → `BoardSceneAdapter.install()` → `MainGameManager.board: BoardRuntime`。

源码目录：`res://scripts/battle/board/`。空间索引只管理地块身份、地址、几何与平台；实际植物占用和创建/释放事务仍唯一属于 `PlantCell`，卡牌费用仍由 `signal_card_use_end` 结算。没有第二份占用矩阵。

未设置 `board_definition` 时，由适配器读取原场景，保留原节点路径、坐标和攻击行。现有六关没有改成示例尺寸或新布局。旧 `terrain_rows` 仅在此兼容入口生效；与显式布局同时配置会被拒绝。

## 关卡作者怎样配置

在 Godot Inspector 新建 `BoardDefinition` 资源并挂到单关覆盖的 `board_definition`，不用修改植物脚本。规则矩阵可选择其子类 `BoardGridDefinition`；两种定义展开后走相同运行时。

| 声明 | 必填或关键字段 | 含义 |
|---|---|---|
| `BoardDefinition` | `board_id`、`revision`、`lanes`、`surfaces`、`cells`、`terrains` | 完整静态空间；不兼容拓扑变更递增 revision。 |
| `BoardCellDefinition` | `cell_id`、`address`、`surface_id`、`position`、`size`、`terrain_id` | address.x 是零起点攻击行，address.y 是逻辑列；position 是平台局部像素坐标，size 是交互范围，不缩放植物美术。 |
| `BoardLaneDefinition` | `lane_id`、`spawn_position`、`spawn_type`、`mower_position`、`mower_kind` | 固定攻击行；出生点和清洁车位置使用主战场局部坐标，不由植物格数推测。 |
| `BoardSurfaceDefinition` | `surface_id`、`origin`、`travel_offset`、`travel_seconds`、可选 `visual_scene` | 一个可独立移动的平台，平台内所有格子与植物整体随动；零位移表示静态。 |
| `BoardTerrainDefinition` | `terrain_id`、`planting_flags`、`supported_flags`、`spawn_type`、`tags`、`blocks_planting` | 地形能力；supported_flags 在存在 Down 承托植物时使用。 |

**自定义离散坐标**：可以只声明逻辑地址 `(0,0)`、`(0,4)`、`(1,2)` 的三个种植点，各自设置不同 position/size。中间不存在的地址不会创建占位格，也不会被当作压缩数组的下标。cell_id 在位置变化、资源数组重排时保持不变。

**非矩形点击范围**：`hit_polygon` 的顶点在该格 size 的局部范围内；空值使用矩形。Button 命中和移动后的实时拾取共用此几何与 GUI 场景树顺序，界面菜单/卡槽优先，不穿透 GUI 种植。HandManager 统一解析悬停/点击目标，禁止各信号独立覆盖目标。普通僵尸卡资格统一调用 `ZombieManager.can_place_zombie_at_cell()`，预览和提交不能分叉。

**邻接关系**：默认按同平台逻辑地址计算范围；`explicit_neighbors = true` 后改为 `neighbor_ids` 的有向步进关系。需要双向相邻时应在两端都声明。`right_neighbor_id` 可单独声明玉米加农炮等多格植物的向右占格；目标必须同平台、同攻击行。不能让一株多格植物横跨两块独立移动平台。

**规则网格**：`BoardGridDefinition.dimensions` 是行列数，`pitch` 是列/行像素间距，`grid_origin`、`cell_size`、`grid_surface_id`、`default_terrain_id` 控制生成。`column_edges` 与 `row_edges` 可各自提供平台局部坐标中的格线，分别包含最外两条边界。`cells` 可按 `address` 覆盖个别点，显式 `lanes` 可覆盖生成的攻击行。

**连续水域**：致幻洋流的 `wonderland_psychedelic_current.tres` 将种植、出怪与清洁车一起配置。地块使用水面种植能力，`default_lane_spawn_type` 设为 Pool，`lane_baseline_inset` 将出怪与清洁车脚点设在同一行内。平台的 `water_regions` 可覆盖棋盘与盘外出生区，使用共同的水体接触检测。

**致幻洋流正式关卡**由奇境地图以编号 `AdventureStageRegistry.PSYCHEDELIC_CURRENT`（101）进入 `psychedelic_current_battle.tscn`。关卡稳定 ID 为 `wonderland.psychedelic_current`，通关写入 `regions.wonderland`。复用第一关的敌人展示、玩家库存 UID 选卡、商店槽位扩展、卡组确认冻结、奖励落盘与阶段续战。初始阳光为 **50**，普通 → 噩梦 → Boss 在同一局中连续进行。每十波一旗。普通 40 波全 2 阶，前中期出怪适中，后期增加。铁栅门、海豚和铁桶分别在前三旗固定出场后加入随机池。噩梦 50 波，随机池中 2、3 阶等权抽取。前四旗分别固定出五只读报、3 阶铁栅门、3 阶铁桶和橄榄球，部署在第 1 至第 5 路。旗僵由每旗的预排组生成。

噩梦第 50 波清空后明灯自动登场，生命值为 120000。每八战斗秒启动一轮，五轮普通行动后强制滔天，入场及滔天回场后重新计时。低于半血立刻发动强化滔天，回场时切换至星空形态。二阶段的普通行动每轮随机连放两个不同技能。遭遇期间每 5 秒从噩梦自然池生成援军，一阶段 2 只，二阶段 3 只，存活上限 8。全阶段关闭小推车、补车及右侧待入场两倍加速。

正式配置位于 `resources/adventure/stages/wonderland_psychedelic_current.tres`。`StageDefinition.battle_scene/return_scene` 指向专属战场与奇境地图；统一 `SceneTransition` 接纳目标后才发布会话，胜利、失败与放弃均返回奇境。噩梦或 Boss 中重开遵循当前模板，重新选择卡牌并从噩梦第一波开始；`StagePhaseDefinition.board_definition/background_texture` 负责重开的正确地形与底图，演出节点恢复对应 Skybox，不重复播放巨浪或再次删列。

奖励表以第一关的普通/噩梦材料与配方表为模板，资源独立放在 `resources/adventure/drops/wonderland/psychedelic_current/`。普通清场固定获得一把本关噩梦钥匙，进入噩梦通过既有保存事务消耗一把；不再掉落或消耗本关终末钥匙，已有库存不删除。Boss 击败事件复用第一关噩梦掉落模板，首通钱币、重复结算保护与存档失败回滚沿用原实现。普通通关后，地图悬停情报用既有 `StagePreviewData` 显示普通、噩梦及其 Boss 遭遇的敌人和掉落。

选卡镜头保留原版从 X=-150 到 X=120 的两秒横移，确认后返回 X=-150。`CanvasLayerBG/RightSeaExtension` 镜像复用海面原图及同一材质，为横移后的右侧视野延展画面；它不创建种植点、水体或加速区。独立 Skybox 持续覆盖视口，敌人展示框位于选卡镜头的右侧可见范围。噩梦重开也替换延展层的图与材质，四张原始图片不做编辑。

普通为 **6 行 × 10 列全水域**；噩梦使用 `wonderland_psychedelic_current_nightmare.tres` 的 **6 行 × 9 列全陆地**，Boss 沿用噩梦布局。噩梦原图尺寸为 1672×941；列界源像素为 `[288,432,576,723,871,1023,1174,1323,1471,1620]`，行界为 `[146,264,382,498,614,735,854]`，首列左界被船体部分遮挡，按相邻可见格距外推。显示转换为 `(-150,64) + 源坐标 × (1066/1672,536/941)`；逐条格界换算为 `column_edges`／`row_edges`，不复用普通版格距。出怪横坐标为 965，各行脚点在下界内侧 10 像素；船边失守判定同步调整。图片、种植范围与点选使用同一组坐标，植物美术本身不拉伸。

**巨浪入水转场**：确认进入噩梦后，`psychedelic_current_transition.gd` 在原续战暂停期间播放 4.8 秒演出，不受战斗倍速影响。浪头沿画面纵向压近，卷浪泡沫、屏幕折射和相机下沉使用同一时间轴；2.15 秒水幕完整覆盖时，同步更换棋盘与独立 Skybox，再从水下逐渐显露新场景。正常完成或离场均恢复镜头，音乐音量始终不受环境处理影响。普通、噩梦四张原始场景图保持不变；噩梦独立天幕与地板动效、柔焦、折射和音效统一由[环境配置](psychedelic_abyss_environment.md)驱动，Boss 遭遇继续使用同一套环境。新增 `breaker_foam.png` 是独立透明特效素材，`psychedelic_current_breaker.wav` 是本次合成的短浪声音效，走现有 SFX 总线。

转场前 `BoardPhaseLayout.prepare()` 检查同攻击行、同平台、同格子身份的收缩布局，并离树准备地形层。全覆盖时提交：删除第 10 列全部占用，不触发亡语或复活归档；前 9 列的格子和植物保持原实例，只更新几何、地形与出怪资格，保留血量、计时器、阳光和卡牌冷却。原有荷叶及其上植物一并继承；新种植遵循陆地规则，可裸地种植陆生植物，不可再种荷叶。旧水体接触节点全部移除，选行器重新读取陆地资格。

加载仍由统一 `SceneTransition` 承担：战场根脚本 `psychedelic_current_battle.gd` 通过已有 `get_initial_resource_paths()` 协议声明普通、噩梦及 Boss 遭遇的僵尸/Boss 依赖，入场时后台准备并由目标场景保留引用，避免转场末帧同步加载敌人。噩梦图层与材质在入场遮幕期间预热，无新增全局缓存。

**致幻洋流战斗动效**：`psychedelic_current_battle.tscn` 的 `CurrentEffect` 分别驱动海面与 Skybox 材质，复用两张原始图片。`psychedelic_current_effect.gd` 将权威 `row_edges` 换算为海面 UV，主浪纵向推进，七道浪峰围绕六行格界聚集，波谷位于每格内部。默认峰顶局部翻卷不超过 1.34 屏幕像素，逻辑格子和种植位置保持不变。水面、天空和色光使用同一组有界相位，暂停冻结、恢复续播，战斗倍速不改变环境演出速度。场景实例的 `motion_speed`、`wave_strength`、`light_strength`、`color_strength`、`sky_strength` 是入场时的调参入口，种植与水路数据仍只在棋盘资源中配置。此专属海面着色器按当前六行原画制作，不作为任意行数布局的通用着色器。

**致幻洋流战斗音乐**：`resources/adventure/audio/psychedelic_current.tres` 集中引用普通、噩梦、Boss 三首原始 MP3，导入设置均开启循环。`ResourceLevelData.battle_music_profile` 与阶段环境引用同一资源；普通/噩梦身份统一读取 Session。入水时保持背景音乐音量，在水幕交接点切噩梦曲。明灯遭遇开始时立即停止背景音乐，完整入场后再播放 Boss 曲。退场恢复当前阶段曲目，相同曲目继续播放。阶段显式配置的音乐优先于此组合。

## 运行时唯一入口

花园飞艇为 5 行 × 17 列的稀疏棋盘，配置见 `boards/wonderland_garden_airship.tres`。从左到右，每两列放一块 2×2 浮台。初始位于第 1–2 行的四块浮台先向下移动，第 4–5 行的四块先向上移动，单程跨三行，耗时 8 个战斗秒。第 17 列是固定的五格长桥，共有 37 个可种植格。每个甲板的 `grid_rect` 和 `turf_rect` 分别记录初始逻辑区域与原画草皮内的点击范围，格子与 `visual_scene` 共用同一个 `BoardSurface`。

飞艇显式开启 `project_surface_combat_lanes`。种植、邻接和存档使用稳定的 `row_col`，持卡虚影跟随实时放置锚点。植物脚点跨过两条僵尸进攻线的中线时，`combat_lane`、索敌与受击随之更新。普通子弹在发射瞬间记录炮口世界位置和攻防行，随后独立飞行。僵尸沿五条固定基线行进。

飞艇棋盘修订 3 保留修订 1、2 的 25 个地块 ID。旧长桥占用随原 ID 恢复到第 17 列，新增浮台从空草皮开始。修订 1 的共用甲板会拆分到对应平台，修订 2 的原有浮台从保存的往返进度继续移动。转换在快照副本上完成，跨两块独立甲板的旧多格占用仍由恢复事务拒绝。

花园飞艇的环境由 `garden_airship_battle.tscn` 中的 `FlightEnvironment` 驱动。环境时钟独立于战斗倍速，随战斗暂停并在重开时归零。交战子时钟从正式开战计时，选卡和准备阶段保持巡航。结算阶段让已触发的气流和余风回正。环境姿态只供外界投影和云层使用，战斗相机、平台挂点、输入和角色脚点沿用原坐标。

- `garden_airship_backdrop.tscn` 复用原 `skybox.webp` 的天空和远山。虚拟相机用 60° 视场计算地面射线与平面交点，采样正射绘制的周期花田 `flower_plane_r3.webp`。按交点距离混入蓝色大气，纹理在两个周期上分别回绕。近远光流由投影生成。
- `garden_airship_backdrop.gd` 的 `ground_tile_size` 与 `ground_travel_ratio` 控制田块尺寸及相对于累计航迹的水平和纵深速度。远云、船下俯视云、云底和近云缘用各自深度取样同一航迹及姿态。平台间隙的云与雾丝在船壳之后，船侧与船底擦身云在独立前景画布。
- `garden_airship_atmosphere.gd` 在本局安排云海开口、下降气流、穿越云缘。开口在正式开战约 7–9 秒后出现，后续每个主事件之间保留约 15–20 秒巡航。共用包络同时影响视野倾转、升沉、近云、飘带、吊索中段及环境音频；同一时段只有一个主事件。
- 云缘的局部阴影从可见云底位置投射到船身和九块草皮。角色复用身体环境色通道，原生接触阴影继续按实时甲板裁切。移栽后通过新位置继续取样日照。局内 `FlightAudio` 用三路循环和一路索具短声接入既有 `SFX` 总线，遮幕出现时淡出。Master 在本局采用 −1.2 dBFS 峰值保护，释放场景时移除局内创建的限幅器。来源与处理见飞艇资产目录的 `audio/SOURCES.txt`。
- 自动画质在移动端使用低档。低档保留花田、两片船下主云、云缘光影与环境声，减少前景透明叠层和索具反应。设置里的「禁用特效渲染」逐步减弱外界俯仰、横滚、升沉和近云速度。检查器中的 `motion_speed` 可调整局部演出速率。
- 飞艇上部沿用原采样和吊索锚点。下船壳单独做平滑逆映射，机匣、桨轴、舱徽和底灯按母图的纵横比显示，长度分给平直板面。下缘、桨叶和联接件取样同一映射，双桨帧序继续由 `propulsion_atlas.png` 提供。

<details>
<summary>R3 平面花田与云层制图记录</summary>

内置 ImageGen 以 R2 花田为配色和笔触参考，另制无预绘透视的俯视方图。选定图为 1254×1254，取中心 1248×1248 区域，两轴各用 96 像素重叠、沿自然形状选接缝，并以 23、14、7 像素半宽分频余弦融合。输出 1152×1152 的 WebP Q94，循环边缘经解码和平铺检查后开启 mipmap。

```text
Use case: stylized-concept
Asset: one square full-bleed seamless repeatable ground-color texture for a flat ground projection below a garden airship. Paint a new landscape using the attached image solely as a reference for its brushwork, warm pastel flower colors and teal-hued foliage.
Show a perfect nadir view of a large flower-growing landscape, like an orthographic painting from very high above. Equal scale at all four edges. Ground only. Aim for 20–24 little parcels across the square and a similar number vertically. Every parcel is small and compact, usually 3–6 percent of tile width. Depict irregular, interlocking, short natural shapes with varying orientations, nicked edges and curved corners. Disperse them with the natural non-alignment of a real irregular meadow. Break up and vary their sizes, orientations and spacing throughout the tile. Keep well-separated small patches of soft warm pink, lavender, golden cream and pale yellow scattered through plentiful multiple shades of green. No regular grid, no diagonal alignment, no parallel strips, no consistent repeating sequence of colors and no giant fields. Each individual flower appears only as a tiny irregular hand-painted pigment daub.
Give the ground the soft mottled gouache brushwork and cheerful pastel colors of the reference, with fine dabs inside each parcel and close, tonal transitions from flower patches to grassy sage and yellow-green. A few sparse, narrow, faint dusty straw-colored footpaths and faint grassy field borders add scale. Short clusters of tiny muted teal tree crowns seen directly from above appear intermittently. Keep paths and crowns subordinate to the flowering terrain and scatter visual detail evenly. Flat midday light with soft local color; no horizon, distance shading, sky, dark casting shapes, landmarks, roads, buildings, labels, framing, decorative borders or text.
Treat the entire square as one continuous natural tile. Two opposite edges must join cleanly in each direction, with fields and intermittent greens continuing across the boundary and the same coverage all the way through the corners.
```

云体也用内置 ImageGen 独立生成 RGBA 图。原天幕与主菜单的近云 02、03 用于目视比对。两张选定图去除透明区游离像素，按预乘色缩放，在透明边缘保留少量相邻颜色，输出无损 WebP。船下图 1360×544，云底图 1344×560。

```text
Use case: stylized-concept.
Asset type: transparent cutout sprite for a hand-painted 2D Garden Airship game level.
Subject: one very broad low cumulus bank far below the player, seen steeply from above. Paint the visible sunlit TOP surfaces of overlapping cumulus, with broad creamy-ivory caps and soft periwinkle-blue and lavender cast shadows in troughs between puffs. Read as an aerial field of billows stretching laterally and receding in depth, with clusters of varied sizes and broad luminous planes. No horizon or side-view tower.
Style: soft painted animation background art, flat matte brushwork with visible smooth color patches, pastel sunlit palette, thin warm highlights and cool clean soft shadows. Diffuse clear-day sunlight from upper right. Keep a substantial cloud body that can obscure a flower meadow behind it.
Composition: isolated long asymmetric bank about 2.6 times wider than tall, centered with transparent padding all around. Give the outer sides uneven branching lobes plugging into scattered wisps, deep natural concave scallops and tapered edges that gradually dissolve through real fractional opacity. One side broad and bulbous, the other narrowing into a few irregular wisps. The outer contour should create an irregular growing opening when two instances slide apart over the distant landscape. Keep some transparency in the edge recesses. Broad cloud groups at different scales, no row of repeated equal puffs, no straight flat base or horizontal bands.
Output: real transparent RGBA, subject only, all four edges inside the canvas, no hard cropping. No sky color, backdrop, checkerboard drawn into pixels, extra scenery, text, frame, watermark, outlines or photographic grain.
```

```text
Use case: stylized-concept.
Asset type: transparent cutout sprite for a hand-painted 2D Garden Airship game level.
Subject: a single immense cumulus ceiling passing overhead. Viewed from underneath with nearly all the visible volume formed by underside billows, broad hanging bulges in overlapping depth, and a deep receding center. A few particularly large downward billows and smaller divergent side wisps establish scale. A broad cool slate-blue and lavender-gray half-shadow covers the dense belly with transitions through several blue-gray values. Creamy soft pale sunlit edges come from the upper right at the outermost rim and a few rim-facing lobes. Fair-weather bulk with readable half-shadow, no storm menace.
Style: soft hand-painted gouache and pastel animation background artwork with clustered natural brush planes, clean color and lighting, visually compatible with pastel ivory-and-periwinkle airborne clouds. No photographed texture.
Composition: a wide cohesive organic ceiling mass about 2.5 times wider than tall, asymmetrical and slightly diagonal, with wide transparent margins around the entire object, unequal hanging lobes and a deliberately irregular underside. Make the top rim uneven. Mix big and small billows. Transparent edge wisps melt into clean outside alpha, and the dense underside stays substantial. Shape should read with part of it entering the upper screen edge, without any straight horizontal edge or repeated stripes.
Output: real transparent RGBA, subject only, all four edges inside the canvas, no hard cropping. No sky color, backdrop, checkerboard drawn into pixels, scenery, text, frame, watermark, outlines, or lightning.
```

</details>

<details>
<summary>R1 远景花带生成记录</summary>

内置 ImageGen 使用原 `skybox.webp` 作为色彩、笔触和地貌参考。选定图为 2172×724，面积采样缩放为 1920×640 WebP，质量 87。

```text
Use the supplied hand-painted background from a 2D game as a color, medium and landscape reference. Deliver a separate game parallax texture layer consisting ENTIRELY OF THE FARAWAY FLOWER VALLEY GROUND, a wide 3:1 panoramic strip, no sky, no clouds, no foreground objects. The airship viewer is now floating roughly a kilometer above that beautiful valley. Take the middle-distance thin ribbon of pink, lavender, soft white, sunny pastel yellow flower fields and sage-green hedgerows between the mountains and close foreground of the reference, and develop that distant landscape across the full new image. TOP edge: very distant, flat, pale powder-blue atmospheric valley recedes into haze; spans from left to right horizontally, with no sky or discrete peaks. TOP HALF: many extremely fine, small flattened ribbons of color recede into that far distance. LOWER HALF: broad graceful, gently rolling horizontal and diagonal patches of blush-pink, purple, buttery yellow, mint, and green, separated by small copses and soft field boundaries. Painterly irregular grouped color shapes at varied natural intervals. Use irregular field shapes and clusters instead of regimented farm plots. Even at the bottom edge it should look like the earth far below, an airy high-oblique map of broad fields. Individual flowers are too small to resolve; no visible petals, flower centers, daisies, or large trees anywhere in the image. Use the pale yet cheerful gouache colors, animated film background artistry, gently brushed soft light and restrained contrast from the reference. Keep it richly hand-painted and luminous. Fill the entire panel with this vast flower valley. No ground-level vantage, no grass stalks, no close-up blossoms, no clouds, sky, ship, UI, grids, border or text. Think a long seamless lateral pan, similar scale, value and palette at left and right edges; no centered hero motif. Single continuous illustration.
```

</details>

<details>
<summary>R2 高空花田生成记录</summary>

内置 ImageGen 以原 `skybox.webp` 为笔触和配色参考。第一遍建立二维田块构图，第二遍以第一遍的画面与原天幕为参考继续拉高视角。选定图为 2172×724，裁去左右各 1 像素和底部 104 像素后，用 Lanczos 等比缩至 1792×512，保存为质量 90 的 WebP。

第一遍提示词

```text
New derived hand-painted terrain texture for the user's own illustrated game. Use the supplied painting ONLY as a style and palette guide (its soft sunny gouache fantasy garden hues). Paint a NEW panoramic 3:1 terrain-only texture edge to edge for an airship high above a mass of flowering parkland. No sky, horizon, clouds, mountains, board, props or text anywhere. View steeply down across an intricate natural mosaic of COMPACT two-dimensional irregular meadow parcels. Make many separate, fully readable rounded-triangular, bean-shaped, quadrilateral, oblique and nearly round flower fields of varying size and directions, each with depth comparable to its width. Broken angled green hedgerows, small groves, subtle branching grassy seams and occasional quiet meadow openings connect them. Asymmetric nonrepeating landscape with distinct shapes, avoid rigid village/farm grid and endless little identical confetti. Main foreground pink, gold, muted lavender, warm creamy-white plantings with fine painterly flecks in a sea of light spring greens and soft blue-green distant copses. Most pigment lies in extensive masses of flowers, flower heads minuscule. Camera is high enough to see many fields; nearest typical parcel about 1/14 image width, heterogenous. Lower edge shows clear shapes, only subtly smaller toward the upper edge, a continuous ~3:1 scale gradient; upper edge entirely distant tiny pastel cool blue-green meadows, no horizon line. IMPORTANT avoid elongated horizontal parallel bands, horizontal crop rows, hill silhouettes, rainbow stripes, broad frontal slopes, and horizontal brush smears EVEN IN THE FOREGROUND. Make many patch boundaries point near vertically up the picture, mixed with diagonals and branching curves. Natural sunlight, expressive but soft real paint marks, atmospheric yet readable, fantasy game environment background designed to remain quiet behind the characters. No giant individual flowers, trunks, houses, buildings, windmills, haybales or landmarks. Only seamless-looking land, no sky, no border. Wide panoramic landscape format, 3:1.
```

第二遍提示词

```text
Repaint first image as the same land from an airship at roughly THREE TIMES HIGHER ABOVE THE GROUND. Use second illustration only for the existing distant blue atmospheric atmospheric palette. First image has the right irregular parcel shapes and style, but camera is much too low: image must become A WIDE, QUIET ESTABLISHING SHOT OF A VAST VALLEY. Very wide 3:1 edge-to-edge texture, terrain only, existing sky/horizon handled by separate layer; DO NOT draw sky, clouds or hills. At the bottom of this wide image you can see 17 to 25 varied medium-size irregular flat parcels across, not 5 fields! At top, many more and smaller parcels, topmost edge completely blue-green and hazy like the original skybox's farthest mountain foothills, so it will seamlessly blend under that distant ridge. Foreground masses hand-painted in homogeneous colored brushstrokes with extremely tiny texture. Individual flower faces or recognizable petals INVISIBLE at this great height. Foreground soft pink, lavender, yellow and cream fields interspersed with moss green meadow openings that occupy about 1/3 of visible land. Tree groves from far above are low-relief tiny tonal shapes, no separately articulated trees, canopies and trunks. Soften strong yellow, pink and white. Rich hand-painted natural variation with quiet farmland and organic irregular compact forest clearings far below a flying ship. Do not draw farmhouses, buildings or roads. No repeated units of same size or orientation, no long horizontal bands or waves, no parallel crop rows, no rectangular grid. Compact and legible 2D mosaic parcels with meaningful vertical and diagonal structure, avoid foreground petals, polka dots, giant flowers, evenly dotted texture and hard contrast. No added text or icons. This is panoramic game backdrop art that recedes very far behind the hero.
```

</details>

以下调用针对当前战斗 `game.board`，不创建新的全局单例：

```gdscript
# 稳定身份查询；不存在返回 null。
var cell: PlantCell = game.board.cell_by_id(&"ferry_plant_a")

# 稀疏逻辑地址查询；缺格返回 null，禁止使用压缩枚举行下标。
var target: PlantCell = game.board.cell_at(Vector2i(1, 4))

# 将平台移到主战场局部坐标，用两秒有效战斗时间完成。
var moving: bool = game.board.move_surface_to(&"ferry", Vector2(160, 0), 2.0)

# 换地形默认拒绝有植物/障碍的格子；失败完全不扣费、不铲除植物。
var changed: bool = game.board.set_cell_terrain(&"ferry_plant_a", &"mud")
```

`move_surface_to()` 接受平台目标坐标，秒数为零时立即定位。显式移动覆盖自动往返，完成后停在终点。自动运动与过渡只在 MAIN_GAME 推进，遵守场景暂停。地块 ID、逻辑邻接和占用始终稳定。攻防行默认取逻辑行，开启 `project_surface_combat_lanes` 时由平台按脚点更新。

`set_cell_terrain(..., true)` 明确允许保留现有占用，包括与新地形不兼容的植物；不会自动摧毁、迁移或退款。地形变化通知使用 `board.terrain_changed`。单个来源临时禁种使用 `cell.set_planting_block(source_id, blocked)`，不得通过改其他效果的标志来解除自己的限制。

查询统一使用 `cells()`、`row_cells()`、`cell_at()`、`neighbors()`、`horizontal_neighbors()`、`right_of()`、`nearest_cell()`、`local_pitch()`。`PlantCellManager.all_plant_cells` 仅为旧枚举消费者提供只读行副本，不能用 `[行][逻辑列]` 访问稀疏布局，也不能写回数组。

## 特殊地形扩展

`BoardTerrainDefinition.behavior_scene` 的根必须继承 `BoardTerrainBehavior`；所有实例化均经 `create_behavior()` 检查可实例化性、空实例与根类型。`BoardTerrainLayer.prepare()` 完成离树构造和状态预检后才可安装，不在释放旧层后继续尝试构造。每个地块创建独立实例。扩展脚本通过 `cell` 访问当前占用，覆写 `tick(delta)`、`removed()`，需要持久化时实现 `capture_state()` / `accepts_state()` / `restore_state()`。验证方法必须是离树可调用的纯校验，不能依赖 onready、玩家库存或当前战斗。

新植物对特殊地形的要求使用 `ResourcePlantCondition.required_terrain_tags` / `forbidden_terrain_tags`；不要给 PlantCell 的地形枚举不断追加物种分支。`presentation_kind` 只负责旧美术分类，不能替代生成条件 `spawn_type` 或种植能力。

`water_contact = true` 从本地块矩形/多边形生成随平台移动的 `WaterBodyArea`。它只提供接触，不自动生成水面纹理；表现由行为场景或平台 visual_scene 配置。原场景水面仍由 `WaterSurfaceProfile` 区域承担视觉和物理接触；制作新布局时必须配套校准环境区域，避免重复或错位水体。

`SwimBoxComponent` 聚合多个水体接触，最后一个水体离开才出水；普通/潜水表现只覆写聚合状态回调。普通下沉取消旧过渡并从固定基准求目标位置，不能在每次进入相邻水格时再累加下沉量。

## 存档与生命周期

`ResourceSaveGamePlantCellManager.board_state` 保存布局 ID/revision、地块身份与逻辑地址、地形及行为状态、平台运动阶段、攻击行身份顺序。植物和墓碑新档按 cell_id 恢复；只有原布局兼容旧 row_col 档案。

正式恢复统一走 `BoardRestoreTransaction.prepare()` → `commit()`。`BoardStateRestore` 负责空间计划，`BoardRestoreEntities` 校验并预留全部植物/墓碑/梯子；准备阶段不写活占用。未知/重复 ID、拓扑不兼容、字段缺失或类型错误、物种槽位不匹配、多格重叠、结构冲突全部拒绝。空白场地校验与全部资源构造成功后，才同步恢复平台、地形、依赖结构、承托与植物；不重做扣费，也不容许中途跳过失败记录。

正常种植与读档共用 `PlantPlacement` 离树构造及 `PlantCell.commit_prepared_plant()`，两条路径不得各自维护占用。恢复按 Down 承托层优先，与存档记录顺序无关。全部占用就绪后先从真实实例重建数量，再发布创建事件；整个提交/发布期间由 BoardRuntime 令牌拒绝重入。

植物基础恢复校验由 `Plant000Base.accepts_save_state()` 提供；物种新增持久化字段时，在该物种覆盖此纯离树方法并调用 super，不能只在加载函数中直接取未验证字段。依赖墓碑共占的植物通过 `ResourcePlantCondition.requires_tombstone` 声明结构关系；普通植物与墓碑冲突时整份恢复失败。

常态战斗的地块身份集合固定，移动须走平台，不直接重挂/释放格子或改 address。阶段交接仅可通过 `BoardPhaseLayout` 在暂停期间安装已预检的收缩布局；该入口不是自由增删地块 API，不支持新增格子、改变攻击行或动态水体地形。承托层仍使用格子 Control 锚点与 Content Node2D，植物、壳体、受击盒和交互随节点变换移动；禁止缓存初始世界坐标后回填。

## 明确边界

本轮支持规则或稀疏种植点、任意点位配置、矩形或多边形点击区域、平移平台与地形行为扩展，以及暂停阶段交接时的预检收缩。连续无格种植、平台旋转缩放、任意增删地块、跨行占用迁移与自由寻路仍在支持范围外。进攻线由布局固定。按实战行查找地块用 `row_cells(lane)`，按原逻辑地址读档或查询邻接用 `cell_at(row_col)`。

原版 Boss 大型美术、背景、镜头、屋顶坡面和部分按行/像素范围技能仍需与新关卡几何配套；空间资源不自动拉伸美术，也不保证任意战场布局下所有原版攻击范围与演出都已验收。显式图邻接用于拓扑技能；矩形爆炸仍按实际像素几何判断。

验证遵循仓库 `AGENTS.md`：默认不新增、不运行测试；修改时只修复已有测试的失效接口引用。编辑器导入/解析不能替代移动平台、荷叶多层随动、原版泳池、正常卡槽扣费和读档的实机终验。

## 卷浪素材来源

`assets/adventure/wonderland/battle/psychedelic_current/breaker_foam.png` 使用内置 ImageGen 的 generate 模式、`transparent_background=true` 生成，1536×1024 RGBA，保留生成结果的原始透明通道。未编辑用户提供的背景。最终生成提示如下：

```text
Create ONE production-quality transparent VFX texture atlas asset for a premium hand-painted fantasy strategy game, landscape wide 1536x1024. Subject: a single huge translucent turquoise ocean breaker seen front-on as it rolls toward camera, wide panoramic continuous wave crest spanning beyond left and right edges, no horizon or environment. Intended to be warped and animated as a horizontal scrolling sprite across a game screen. Occupy the central vertical 60 percent of image with a dense curling lip of seafoam: thick sculpted luminous ivory and very pale cyan foam along an irregular but connected long arc, intricate lace-like rivulets stretched downward, heavy deep teal shadow beneath the curling lip, smooth aquamarine glassy tubular water above it, subtle violet iridescent reflections. A real three-dimensional rolling wave, rich painterly illustration like high-end fantasy game background, physically coherent foam clusters flowing into each other, pleasing broad organic shapes with finely detailed edges. Most dense opaque crest runs across at 50 percent image height, painted teal water body continues upward and fades to transparent near upper edge; fine sprays and tendrils taper into genuine transparency below the crest at 85 percent image height. Connected broad waveform with gentle height variations left-right, not a tsunami mountain or a narrow isolated splash. Natural uneven froth and directional streaks, no uniform repeated circles, no neon laser line, no lightning, no stars, no icons, no text, no grid, no scenery, no beach, no boat. Actual transparent alpha background; do not paint black or white backdrop or checkerboard. High definition material detail with large coherent curled volume and deep shaded underside. This is a new independent effects asset; do not modify any game background image.
```
