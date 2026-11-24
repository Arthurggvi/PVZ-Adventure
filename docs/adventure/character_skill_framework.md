# 角色主动技能｜权威架构与接入边界

初始园丁、「吃白饭的大肥鱼」、向日葵娘、新春小璐和雨季邮差·米露已接入主动技能。其他时装按各自配置决定是否有技能。

## 一条权威链路

1. `EquipmentDefinition.active_skill_id` 是可选的资源引用（空表示无技能），不更改装备 UID、存档格式或商店上架策略。
2. 战斗接纳时，`AdventureSession` 通过 `CharacterSkillLoadout.active_skill_id` 冻结技能身份。已载入档案没有有效时装时使用园丁技能；有有效时装时使用该时装的配置。`character_skill_id_for(level)` 校验战局和档案，跳过选卡和连续阶段也沿用入场快照。
3. `CharacterSkillCatalog.DEFINITION_PATHS` 是唯一技能 ID→资源路径白名单；只在实际绑定时加载 `CharacterSkillDefinition`，包含名称、图标、冷却秒数和 `CharacterSkillEffect` 效果资源。
4. `MainGameManager.character_skill_runtime` 属于**整个战斗场景**，不是会在续战时销毁的 `AdventureBattleRuntime`。只在确认后 `bind_skill` 一次，直到退出/重新挑战才释放冷却。
5. `CharacterSkillHud` 呈现图标、冷却遮罩与键帽，并给战斗头像绑定透明的原生按钮。技能按钮、头像、快捷键和手机双指张开均调用 `CharacterSkillRuntime.try_activate()`，共用一个施放事务和冷却；不读取存档或直接修改敌人。首次绑定有效技能时立即切换可见状态，并由 `MainGameManager._layout_character_skill_hud()` 跟随战斗头像框的实际位置与缩放，视口变化不沿用旧坐标。
6. `CharacterSkillContext` 绑定关卡、棋盘、回合和当前阶段；已过期的上下文不能继续命中新阶段。
7. `CharacterSkillTargetQuery` 统一读取 `ZombieManager.all_zombies_2d`、独立 Boss 名册和可选敌方设施；去重、跳过魅惑/死亡/跨场景，不复制造怪名单。
8. `CharacterSkillControlGateway` 使用已有 `AdventureDeepCold` 控制状态。它仅作寒冷适配，不隐式触发寒冰菇的伤害、珊瑚抑制、波次暂停。Boss/设施及条件性冻结抵抗继续由物种本身判定。
9. `CharacterSkillRuntime.cast_committed` 统一触发 `CharacterSkillCutIn.play(skill)`。所有可施放角色技能的冒险关卡和阶段共用斜切入场、多层速度线和斜切退场。演出按实际时间计算、放行输入，暂停或离开正式战斗时清除。

## 新增一个技能的唯一流程

- 新建 `CharacterSkillEffect` 的派生资源脚本，实现只读 `can_execute(context)` 和同步提交 `execute(context) -> bool`；返回 true 的前提是真正完成战斗效果。
- 新建 `CharacterSkillDefinition.tres`，设置稳定 `id`、`display_name`、`description`、`icon`、`cooldown_seconds` 和派生 `effect`。需要开局冷却时，启用 `starts_on_cooldown`。
- 在同一资源内给 `cut_in_portrait` 引用人物原立绘，给 `cut_in_title` 指定专门绘制的透明技能名字图，并设置 `cut_in_accent`。大肥鱼的冰棱字图位于 `assets/adventure/ui/player/skill_titles`。缺少演出素材时分别使用技能图标和 `display_name` 补位。
- 在 `CharacterSkillCatalog.DEFINITION_PATHS` 加入一个稳定 ID 到该 `.tres` 的映射。
- 在对应 `EquipmentDefinition` 的 `active_skill_id` 中填入此 ID；不修改 `PlayerEffects`、`AdventureBattleRuntime`、HUD 或玩家存档。
- 若效果需要枚举目标，调用 `context.hostile_targets(bosses, structures)` 并使用 `CharacterSkillTargetQuery` 的资格方法；特殊冻结复用 `CharacterSkillControlGateway.apply_deep_cold`，不可直接写敌人速度为零。
- 有延时行为时，`execute` 同步创建战场持有的动作节点或时间轴，之后按 `CharacterSkillContext` 捕获的战局身份继续兑现。一次施放只提交一次冷却。

## 时钟、输入与免疫

- 启用 `starts_on_cooldown` 的技能首次开战即进入完整冷却。成功施放后重新开始完整冷却。计时使用战斗游戏秒，暂停时停止，二倍速时加快，连续阶段保留剩余时间。无目标、阶段结束、加载失败和输入冲突不消耗冷却。冷却结束后停表。
- 桌面默认 Q，复用 `ConfigService` 的物理快捷键、冲突校验与 `GameSettingsWindow` 的键帽 UI；鼠标和触屏均可点击技能按钮或战斗左上角头像。手机另支持双指向外张开，不显示物理键帽。动态注册 InputMap 动作，不更改项目既有快捷键记录。
- Boss 及其分身共用 `can_receive_negative_effects`，免疫通用战斗负面状态。柯洛的 TMC-112 使用 `can_receive_clockmaker_slowdown` 与专用行动倍率入口，覆盖在场和持续期间入场的 Boss 及其分身。主动技能按 Boss 当前受击窗口结算直接伤害。敌方设施免疫负面状态，气球和持杆跳跳使用自身寒冷抵抗规则。新增寒冷来源须遵循 `can_receive_cold`，新的抵抗规则须通过统一的物种能力协议与行为树响应实现。
- 大肥鱼对场上当前敌对僵尸施加 5 秒深寒，遵循上述寒冷抗性。首次开战和每次成功施放均进入 90 游戏秒冷却。
- 园丁开战即就绪。成功施放会立即清空当前出战卡槽内所有卡牌的剩余冷却，并进入 90 游戏秒冷却。只有在途冷却会刷新，卡牌仍按原有费用和关卡条件判定可用性。
- 向日葵娘开战即就绪，冷却 90 游戏秒。每株存活友方生产植物立刻额外生产一次，沿用本株成熟度和转职产量。睡眠只在此次生产中豁免，原生产时钟继续运行。随后在当前可见棋盘分区错峰投放 10 枚各 25 点阳光，沿用原生收集，尚未生成的阳光不会跨入下一阶段。
- 新春小璐开战及成功施放后冷却 90 游戏秒。前三爆从后四逻辑列无放回抽选，末爆从其余列抽选。每爆先发外圈再发错开方向的内圈，每圈 14 支仙人掌尖刺，每支对路过的不同敌人各结算一次 50 点基础伤害。尖刺与局部爆光分两批绘制，弹道沿真实受击形状连续扫掠，续战时回收。
- 邮差开战即就绪，冷却 60 游戏秒。当前背包每种植物只取最高星的配方，先无放回抽三种，种类不足才再次抽样。三张临时卡均在原星级基础上升一星、最多十星并继承转职。卡片错峰弹出、落地后可零费种植一次，阶段结束时收回。
- 莫伊的「冥镰裂地」开战及成功施放后冷却 90 游戏秒。以倒数第三逻辑列定中心，刀光从竖直方向倾斜 30 度并覆盖首尾行。峰值帧按刀身轮廓与敌方实际受击框的重叠结算 3000 点基础伤害，同步触发闪屏与震屏。存活且可受负面状态的实际承伤者灼烧 3 游戏秒，每半秒结算 20 点基础伤害，共六跳。伤害沿用原有防御与转伤规则。
- 「冥镰裂地」的落斩声音是两段 CC0 素材的混音，使用 GammaGool 的刀风和 Qvantor 的低频爆鸣。[Powerful Slice](https://freesound.org/people/GammaGool/sounds/860285/) / [Synthesized Explosion](https://freesound.org/people/Qvantor/sounds/879282/)
- 提拉米苏的「花冠守护」开战及成功施放后冷却 120 游戏秒。以场上最靠近屋子的敌人为锚点即时立盾，全行共用 500,000 点生命。屏障拦截迎面的地面敌人和撞上盾面的敌方投射物，在存续的最多 20 游戏秒内为全场植物提供 70% 减伤，新种植与复生也生效。到时或击碎立即撤销拦截与减伤，空场施放不消耗冷却。
- 「花冠守护」的立盾、受击与退场音效使用 CC0 素材混音。[bell1.wav](https://freesound.org/people/Tairblenn/sounds/549898/) / [Magic Whoosh](https://freesound.org/people/DustyWind/sounds/715784/) / [2022-01-14-crystal-bell-08.flac](https://freesound.org/people/arseniiv/sounds/614832/) / [Glass Tap](https://freesound.org/people/zembacraftworks/sounds/427389/)

## 战斗头像与手机手势的输入边界

- `AdventureProfileHud.avatar_control()` 只提供头像节点；`CharacterSkillHud.bind_avatar()` 在战斗中安装与回收点击入口，主菜单和地图上的档案头像不自行施放技能。头像按钮镜像既有技能按钮的可见、禁用与说明状态。
- `MainGameManager` 仅在手机正式冒险战斗中创建 `BattleTouchInput`。它与技能运行时共同属于整场战斗，接收输入资格和施放入口两个回调，不保存技能定义、目标或冷却，也不新增 Autoload。
- `BattleSpreadGesture` 只记录原始触点和间距。第二指加入仅建立候选，普通双指点按、平移与轻微偏移继续交给既有输入，不立即取消或吞掉操作。只有两指各自相对初始连线明确向外移动，并达到总间距门槛时才认领为技能手势。
- 总间距增长门槛取以下三项的最大值：24 个逻辑像素、视口短边的 4%、初始间距的 12%（这一项最多取视口短边的 7%）。每指向外投影还需至少达到 6 个逻辑像素或总门槛的 15%（取较大值）。这样排除同向平移及另一指尚未更新的中间态，允许不对称、斜向张开，无须长按、停留或达到特定速度。固定一指完全不动不视为明确的双指张开。
- 识别在每帧触点更新后执行，真实释放进入 GUI 前也作最后一次判断；已收到的拖动坐标达标时，同帧松开也可确认，无须额外停留。提交意图前同时锁存尝试与输入所有权，因此冷却未结束、目标缺失或效果拒绝时不会在同一次手势中反复尝试。初始间距小于 24 个逻辑像素、第三指加入、系统取消或未确认前离指均使本次候选失效，全部手指抬起后才能重新起手。
- 只有确认张开后才取消尚未完成的 GUI、手套和滑拾按压，并接管原始触摸及模拟鼠标直到全部手指抬起。普通单指沿用原有处理；玉米加农炮在手机上改为松开确认，已认领手势可取消尚未确认的落点。
- `BattlePointerRouter` 仅在当前视口登记本场实例的弱引用。水下透镜在吞掉原始触摸或映射鼠标前调用此入口；事件副本携带处理标记，避免重复识别或使用折射后的距离。
- `CharacterSkillRuntime.is_input_enabled()` 统一禁止在暂停、作弊界面、弹窗、切场遮幕及非活动战斗阶段施放。冷却单独控制实际施放资格，不提前放开已经接管的手势。失焦或退后台会取消旧按压，恢复后必须重新起手。

## 首次战斗操作引导

- `CharacterSkillGuide` 随本场战斗创建，在选卡和准备红字结束、真实头像可见且技能输入门禁开放后显示。等待已有按压结束，不在一次种植操作中途抢走释放；手机通过宿主注入的 `BattleTouchInput.is_pointer_idle()` 同时等待主指、副指及残留模拟鼠标，不另建触点集合。无技能角色不显示，也不消耗首次记录。开局冷却不影响说明的出现。
- 电脑提示点击左上角头像释放角色技能；手机另提示双指向外张开（放大手势）。两端都说明冷却结束后可使用，不要求现场施放或等待技能就绪。
- 复用 `TutorialSpotlight` 的木质说明卡、真实头像高亮、呼吸边框及箭头；说明期间关闭高亮孔的输入透传。教学位于 92 层，在技能演出之上、水下透镜 95 层及切场遮幕 100 层之下，画面与点击继续共用环境映射。
- 通过独立 `TreePauseManager.E_PauseFactor.CharacterSkillTutorial` 暂停战斗。确认、暂缓或场景退出只释放本组件持有的教学因素，不清除菜单、结算等暂停。延迟到达的暂停菜单打开请求同样尊重教学锁。
- 首次记录复用每个玩家的 `AdventureState.tutorial_steps`，电脑与手机分别保存 `character_skill_desktop`、`character_skill_mobile`。旧档缺键视为未看过，无需版本迁移；换端后可了解不同操作。
- “知道了”通过共享 `tutorial_progress.gd` 事务和 `save_now()` 成功保存后才关闭；保存失败回滚完成标记并显示重试。“稍后继续”或返回键只暂缓本场，之后进入关卡仍会提示。任务教学的旧公开方法转发到同一事务，不复制存档逻辑。

## 最小核验边界

- Godot 资源导入及解析、无技能旧时装兼容、未注册技能拒绝激活、默认键位与原有工具不冲突。
- 专属技能验收覆盖开局冷却、施放命中、Boss 免疫、普通→噩梦连续冷却、暂停和二倍速。
- 输入验收覆盖头像与技能按钮共享冷却、手机双指张开与普通平移的区分、失败不重试、多指取消后的种植/铲除/手套/加农炮、暂停和退后台，以及水下折射场景。编辑器资源导入只能验证解析与依赖，触屏手感和系统事件时序仍需真机验收。
- 首次引导验收覆盖新旧档、两端独立记录、确认后不再出现、暂缓与保存失败后可重试、开局冷却和无技能、按压未结束时不插入、跨场景释放自己的暂停，以及水下折射中的说明按钮。
