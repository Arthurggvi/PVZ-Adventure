# 海滨主菜单运行管线

正式场景为 `scenes/main/01StartMenuCoastal.tscn`。地图通过 `MainSceneRegistry.StartMenu` 返回，地区选择由常驻 `AdventureToolbar/MapNavigation` 管理。

- `assets/adventure/main_menu/coastal/texture_catalog.json` 将逻辑贴图名映射为原生纹理资源。 `asset_store.gd` 按宿主复用纹理和精确浮点光场，设计坐标为 1672×941。
- `config/daily_cycle.json` 存放 24 小时环的基准照明。 `menu_clock.gd` 只用本机时间决定光色。船、风、水各有独立周期，动作推进用单调秒。预览通过 `set_preview_hour()` 和 `use_local_time()` 切换。
- `scene_host.gd` 按受光、建筑高亮、陆地风、港口合成的顺序运行。 `effect_profile.json` 控制高亮、灯组和水面。见 [效果接口](main_menu_effects_api.md)。
- `entries.json` 保存命中轮廓、布局和反馈。 `building_entry_layer.gd` 读取工具栏门面权限。图书馆打开图鉴，研究室走任务解锁，港口打开地区选择，档案及退出使用现有保存服务。

制作流程见 [素材管线](../../ASSET_PIPELINE.md#海滨与天气)。 `runtime_inputs.json` 声明发布输入及运行配置。改母图、光场或入口蒙版时重建对应技术资产并核对命中几何。改时刻、灯组或常规动作幅度时编辑对应配置。
