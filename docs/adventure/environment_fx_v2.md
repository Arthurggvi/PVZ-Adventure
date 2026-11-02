# 双地图环境 FX 接入

## 入口与开关

- 主菜单：`scenes/main/01StartMenuV8.tscn` → `ArtCanvas/EnvironmentFX`。
- 僵尸岛：`scenes/adventure/zombie_island.tscn` → 运行时的 `MapCanvas/EnvironmentFX`。
- 两个根脚本均导出 `environment_fx_enabled=true`、`use_clean_sky=true`。
  关闭后者恢复原 PNG 引用并停云；关闭前者隐藏、停止新增 FX 并复原船体。
  既有乌鸦与 BGM 保持原来的生命周期。

## 已接入

- 主菜单：五朵分速云、三层低透明海面高光、六处错峰涟漪、船体微浮动、三个复用烟团节点；保留原有单只乌鸦。
- 僵尸岛：五朵云、三处紫雾、独立相位双瀑布与双水花、毒液流光、四个随机形态/留空周期气泡节点、神殿弱脉冲、四处海岸涟漪。
- 配置集中于 `data/environment/*.json`；共同使用两个小型环境脚本与一个局部遮罩 Shader。
  所有效果是固定数量的 Node2D，位于主体/UI 下方，无 GUI 命中或全局播放器。
- 安装素材只显式追踪运行时所需的 PNG；原始背景没有改写。
  新增海岸遮罩从原 PNG 保守筛选，墓地/脑罩遮罩使用背景局部坐标；生成器为 `tools/build_environment_masks.gd`。

## 检查记录

- Godot 4.7.2：一次 headless editor import，退出码 0，无解析错误。
- 真实 OpenGL Compatibility 图形进程运行 `tests/adventure/test_environment_fx.tscn`，隔离 APPDATA 为 `.godot/fx-test-user`，退出码 0，打印 PASS。
  检查两场景资源/遮罩、层级、总开关、原图回退、船体与按钮位置独立、真实帮助按钮输入、锁定节点、场景释放和原城镇播放器复用。
  地图使用内存状态，不调用保存接口，也不写既有玩家档案。
- 最终运行无 Script/Shader ERROR；原工程 Boss 等资源仍有 invalid UID warning，Godot 沿既有文本路径加载。
- 未进行截图、GIF、长时观察、战斗/存档全面回归。动态美术质量未标记通过。

## 未完成与用户验收

- 树叶摆动/蒲公英：现有树叶烘焙在背景及主体中，无独立叶层或蒲公英素材；需要新增独立素材后才能准确实现。
- 去云图为可逆候选；云痕、节奏、局部遮罩与位置的最终视觉验收由用户完成。
- 最短路径：运行主菜单观察云、海、船、烟、乌鸦 → 选择原生玩家并开始冒险 → 观察岛上云、雾、双瀑布、毒水与神殿。
