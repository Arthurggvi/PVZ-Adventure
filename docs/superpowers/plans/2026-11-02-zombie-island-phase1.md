# 僵尸岛第一阶段实施计划

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在原版主菜单和草坪战斗之间接入六节点地图、戴夫引导和独立进度。

**Architecture:** 地图、节点交互、引导、持久状态、战斗适配分别负责一项功能。复用 ResourceLevelData、ResourceCardReference、CrazyDave 和 MainGameManager，不创建新战斗框架。

**Tech Stack:** 本机 Godot 4.7.2 Stable、GDScript；不更新依赖。

**Spec:** C:/Users/Arthu/Downloads/Codex_Task_Zombie_Island_Map_Phase1.md

## 约束与审计

- project.godot 的主场景 UID 对应 scenes/main/01StartMenu.tscn；冒险按钮原先进入 02AdventureChooesLevel.tscn，使用 change_scene_to_file。
- ResourceLevelData.prechosen_cards 与 CardSlotNorm.init_pre_choosed_card 可直接装入两张初始卡。
- ZombieManager._try_finish_wave 在末波且敌人数为零时请求奖杯；MainGameManager.win_main_game 是奖杯点击后结算；on_zombie_go_home 是实际失败入口。
- Global/SaveService 原存档为 user://<用户名>/GlobalSaveGame.json，另有 main_game_saves_data。冒险使用独立版本文件，并按用户区分。
- 原素材全部存在，未使用 preview；初始 git status --short 为空；不修改 _reference 或原始 PNG。
- 项目 AGENTS.md 默认不测试，但本任务明确要求 Godot 验证，因此添加范围有限的状态和端到端验收脚本。
- 用户已要求完成施工文档；沿用文档的确定设计，直接实施，不另扩充设计与审批流程。使用当前项目供已打开编辑器直接检查，不新建工作树。

## 实施步骤

- [x] 1. 状态适配：scripts/adventure/island_progress.gd。先测重复赠卡、跳过/完成、失败不解锁、胜利持久化、损坏文件保护、新游戏备份。接口 grant_starter_cards / complete_intro / record_victory / start_new / load_progress。
- [x] 2. 战斗适配：AdventureSession 单例与独立草坪 .tres；两张预选卡、10波普通僵尸、原版种植和阳光机制。只在可靠胜利结算修改进度，失败及主动返回地图不解锁。
- [x] 3. 地图与引导：读取 layout.json，在 1920×1080 设计画布中统一等比缩放。六按钮独立图片、Label 和状态层；戴夫复用原场景，精确七句，第四句发卡，跳过也发卡并完成。
- [x] 4. 菜单入口：原冒险按钮进入新游戏/继续游戏选择，新游戏保留旧进度备份并在已有进度时由游戏内确认，继续返回地图。
- [x] 5. 验证：Godot 导入、状态脚本、场景集成和可视检查；真实战斗种植与刷怪；区分自动化触发战斗结果与人工完整打赢。
- [x] 6. 独立代码审查，修复重要问题，输出文件、入口、存档、验收与人工复查记录。

## 重点边界

- 台词4之后退出重启、直接跳过、重复进入地图：数量始终各1。
- 奖杯晚到回调与失败、重复胜利回调：失败优先且只结算当前冒险战斗。
- 新游戏备份失败或存档损坏：提示错误，不静默覆盖。
- 切换原版用户名：冒险状态分别加载，不串档。
- 16:9及其他窗口比例：画布等比留边，背景与按钮共用变换。

## 执行记录

- 已完成前置审计；Godot 可执行文件位于 C:/Users/Arthu/Desktop/Godot_v4.7.2-stable_win64.exe。
- 状态与场景集成验收输出 PASS；最终图形验收含原存档字节隔离、主动退出、改名后继续。执行日志与限制见 docs/adventure/phase1-delivery.md。
- 审查修正：冒险存档随原用户目录迁移；关卡名称偏移由独立 JSON 配置解决遮挡。未改变地图按钮中心与原图。
- 基线已有四张僵王 PNG 缺失引发资源报错，未扩展本轮范围修复。原版草坪验收仍已跑通。
