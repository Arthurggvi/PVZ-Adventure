# 僵尸岛第一阶段交付记录

日期：2026-11-02。依据 `C:/Users/Arthu/Downloads/Codex_Task_Zombie_Island_Map_Phase1.md`。

## 入口与使用

- 主场景保留 `res://scenes/main/01StartMenu.tscn`（原 main_scene UID 不变）。点击原菜单「开始冒险吧」，选择「开始新游戏」或「继续游戏」。
- 新地图：`res://scenes/adventure/zombie_island.tscn`。
- 草坪仍使用 `res://scenes/main/MainGame01Front.tscn` 与原 MainGameManager；配置为 `res://resources/adventure/island_lawn.tres`。
- 初始两张卡以预选种子槽进入战斗，可重复种植，沿用阳光价格和冷却。第一阶段适配参数：150 初始阳光、10 波普通僵尸、原版五行草坪和小推车。
- 胜利沿用「末波清场 → 奖杯 → 点击奖杯结算」。只有已判定胜利且未进屋失败的当前冒险战斗可以写入通关。
- 失败保留原演出后返回地图；战斗菜单的「返回地图」为主动退出，不结算胜利。

## 存档

- 已登录用户：`user://<用户名>/adventure/zombie_island_v1.json`。
- 未登录游客：`user://adventure_guest/zombie_island_v1.json`。
- 常规 Windows 实际目录在 `%APPDATA%/Godot/app_userdata/GodotPVZ-Dream/` 下。
- 文件格式版本为 1，保存 started、intro_completed、stage_1_cleared 和初始卡数量。
- 赠卡句发卡时即保存（现为第七句“拿着这个”）；重复进入、跳过、重新读取都只持有向日葵和豌豆射手各一份。未完成引导而退出，下次从第一句恢复；完成后不重复。
- 新游戏在已有进度时显示游戏内确认，并先复制旧文件为 `.backup-<时间>-<唯一后缀>`。备份失败时不重开。
- 改名随原 UserManager 的用户目录一起迁移；独立文件不覆盖 `GlobalSaveGame.json` 或旧关卡快照。
- 损坏或不兼容文件会明确提示并禁止自动覆盖；胜利保存失败提供重试。

## 文件清单

修改的原文件：

- `project.godot`：注册 AdventureSession。
- `scripts/ui/start_menu/start_menu_root.gd`：原冒险按钮打开新游戏/继续选择。
- `scripts/manager/main_game_manager.gd`：独立胜负结算、失败后返回地图、跳过冒险的原版关卡保存。
- `scripts/ui/ui_main_game_menu/battle_pause_menu.gd`：冒险重试和返回地图。
- `scripts/ui/main_game_ui/trophy.gd`：冒险奖杯不触发原版进度保存。

新增业务文件（每个 GDScript 均少于 200 行，附 Godot 自动生成的 `.gd.uid`）：

- `scripts/adventure/island_progress.gd`：版本化状态、幂等赠卡、备份、原子替换保存。
- `scripts/adventure/adventure_session.gd`：当前用户状态、卡槽适配、场景切换、battle_finished 结果信号。
- `scripts/adventure/zombie_island.gd`：世界地图、布局读取、统一等比画布、关卡提示。
- `scripts/adventure/island_stage_button.gd`：独立 PNG、Label、状态、描边、悬停与回弹。
- `scripts/adventure/island_intro.gd`：原版资源驱动引导接线、跳过、第七句赠卡；表现复用独立戴夫对话封装。
- `scripts/adventure/island_menu.gd`：新游戏/继续、重开确认和错误显示。
- `scripts/adventure/island_ui.gd`：共享控件样式、项目中文字体和系统缺字回退。
- `scenes/adventure/zombie_island.tscn`：地图场景。
- `resources/adventure/island_lawn.tres`：现有战斗资源的第一关配置。
- `resources/adventure/dave_intro.tres`：十一句最终台词原文，使用原版CrazyDaveDialogResource。
- `resources/adventure/island_label_offsets.json`：避免文字遮挡的偏移，不改变关卡中心。

验收与说明：

- `tests/adventure/test_island_progress.gd`：状态持久化和故障保护验收。
- `tests/adventure/test_island_flow.gd`、`test_island_flow.tscn`：真实场景集成验收。
- `docs/superpowers/plans/2026-11-02-zombie-island-phase1.md`：前置代码审计与施工记录。
- 本交付记录。

已有地图素材完整且未修改；未使用 preview，未下载素材，未改 `_reference`。素材仍遵循项目已有 assets 忽略规则，本次没有执行 git add、commit、reset 或 clean。

## 已执行的验证及结果（第一阶段原七句版本的历史记录）

使用本机 `C:/Users/Arthu/Desktop/Godot_v4.7.2-stable_win64_console.exe`，版本输出为 `4.7.2.stable.official.ed1daf0bf`。

1. `--headless --editor --path . --import`：完成新地图贴图导入；检查发现并修正本轮的枚举、类型推断和动画名问题。原项目缺失素材错误见下文。
2. `--headless --path . --script tests/adventure/test_island_progress.gd --quit-after 1000`：最终退出码 0，输出 `PASS: adventure progress persistence, idempotency, backup, corruption protection`。
3. `--headless --path . tests/adventure/test_island_flow.tscn --quit-after 6000`：菜单、七句对白、第四句赠卡、跳过、缩放、两张卡实际种植并扣阳光、进屋失败、自然波次与奖杯、重新读取均输出 PASS。
4. `--path . --resolution 1280x720 --max-fps 60 tests/adventure/test_island_flow.tscn --quit-after 9000`：最终图形运行输出 PASS，并进一步验证主动退出、原版存档逐字节不变、用户改名、实际继续入口不重播或重复发卡。
5. 图形截图检查了第1/4句、地图、两株植物种下后的草坪和胜利地图。已修复草坪文字与营地按钮、下水道状态与底部提示的遮挡。
6. 布局验收在 1280×720、1920×1080、1024×768 三种画布大小检查统一缩放与居中；按钮位置始终来自同一归一化坐标。图形截图为实际 1280×720 窗口。
7. 独立代码审查发现的用户改名和文字遮挡问题已修正并复核；`git diff --check` 通过。
8. 已在用户正在运行的 Godot 编辑器中重新载入本轮修改的 project.godot，保留原菜单场景和编辑器会话。

胜利验收通过自然刷怪十波，使用原项目 `death_all_zombie()` 调试入口缩短清怪时间，再点击真实生成的奖杯。没有直接修改 stage_1_cleared，也没有把点击关卡或退出当作胜利。这证明结算接线与持久化正确；尚未进行无调试辅助的完整手动通关与难度平衡验收。

日志位于 `.godot/phase1-import.log`、`.godot/phase1-progress-final.log`、`.godot/phase1-flow-2.log`、`.godot/phase1-visual-final.log`。图形截图为 `.godot/phase1-intro-1.png`、`phase1-intro-4.png`、`phase1-map.png`、`phase1-battle.png`、`phase1-victory-map.png`。

## 已有问题与本轮范围

初次修改前的 CLI 基线就报告以下原版僵王素材缺失，并导致其部分动画/场景资源引用报错：

- `assets/reanim/Zombie_boss_upperbody.png`
- `assets/reanim/Zombie_boss_neck.png`
- `assets/image/particles/Zombie_boss_iceball_particles_flip_h.png`
- `assets/image/particles/Zombie_boss_fireball_particles_flip_h.png`

因此不能声称整个原工程零错误；本轮新增脚本在最终图形集成运行中没有 SCRIPT ERROR，草坪全流程验收完成。原素材缺失未用网络替代品修补。一次早期 headless 运行还报告退出时残留对象，最终图形验收日志未出现该退出报告。

第二关通关后显示已开放且可点提示，战斗明确标记待后续阶段实装。后五关战斗、Boss/钥匙、2000金币首通奖励、材料、配方、背包/合成/升星、合成屋、任务栏均未实现，符合本轮范围。

## 人工复查

1. 在 Godot 按 F5，从原菜单点击「开始冒险吧」→「开始新游戏」。已有冒险会提示备份后重开。
2. 逐句点击原生气泡，核对十一句原文；第4句短暂停顿，第6句为完整原版应激，第7句展示两张赠卡，第8句收起并播放星屑及prize。另开一局验证直接跳过也获得各一张。
3. 点击锁定节点确认只有提示；草坪进入原版战斗，使用数字1/2或点击卡片种植向日葵和豌豆射手。
4. 手动完成十波并点击奖杯，确认地图开放没落营地；另开新局故意失败，确认不开放。战斗菜单主动返回也不得解锁。
5. 返回菜单→继续游戏，或完全退出后重启→继续，确认对话不重播、卡片数量不增加。
6. 调整16:9窗口大小并尝试非16:9窗口，观察背景等比、节点不漂移、标签清晰；确认悬停放大和按下回弹。
7. 原菜单改名后继续游戏，确认冒险进度仍在。

复跑自动验收时，必须先为测试进程隔离 APPDATA；测试会创建用户并调用改名接口。示例（在项目目录的独立 PowerShell 会话执行）：

```powershell
$phase1OriginalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $PWD '.godot\phase1-test-user'
    & 'C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tests/adventure/test_island_progress.gd --quit-after 1000
    & 'C:\Users\Arthu\Desktop\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --max-fps 60 tests/adventure/test_island_flow.tscn --quit-after 9000
} finally {
    $env:APPDATA = $phase1OriginalAppData
}
```
