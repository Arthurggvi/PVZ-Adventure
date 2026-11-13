# 主菜单效果可达性｜调参、换算法、重建与发布

## 0｜权威入口先置

- 正式菜单：`res://scenes/main/01StartMenuCoastal.tscn`，运行实现 `scripts/ui/start_menu/coastal/`，材质 `shaders/ui/main_menu/`。
- **效果配置**：`assets/adventure/main_menu/coastal/config/effect_profile.json`。正式默认使用内侧暖边高亮、低幅度错相灯光与11.2秒独立水周期。空hover对象恢复当前默认高亮，空lights/water对象仍可用于中性效果对照。
- **当前菜单即时重载**：`menu.reload_visual_effects()`；宿主直接调用 `host.reload_effects()`。返回 `{ok,error?}`，失败保留此前完整有效状态。不会写玩家档案或重建场景。
- **直接调用**：`host.effects.set_hover_effect(...)`、`set_light_behavior(group,...)`、`set_water_effect(...)`、`apply_profile(...)`。`snapshot()`返回深复制；`describe()`列出真实入口和支持范围。
- **离线入口**：`tools/art_bake/main_menu/menu.py`；复现例子：`effects-preview --workspace <独立目录> --tools-config <ArtControl/config.json>`。不加载游戏autoload和玩家存档。
- **示例**：`tools/art_bake/main_menu/effect_examples/`。它们用于说明可替换性，不自动启用为正式美术。

## 1｜三个用户场景怎么改

### 更换 hover 高亮

编辑 effect_profile.hover，例如：
```json
{
  "shader": "res://shaders/ui/main_menu/entry_sweep.gdshader",
  "parameters": {"fill_gain": 0.035, "sweep_gain": 0.28, "period_seconds": 2.0}
}
```

相同对象可随时调用 `host.effects.set_hover_effect(该对象)`。只换ShaderMaterial，现有命中轮廓、权限查询、点击业务、渐入/渐出状态和风/船变换顺序不变。传空对象恢复原材质。

新算法另写一个菜单shader，并保持四项输入契约：`entry_mask: sampler2D`（R可见范围/G既有内边）、`strength: float`、`accent: vec3`、`effect_seconds: float`。其余公开uniform经parameters指定；不允许效果配置覆盖上述输入状态。以Shader实际声明校验拼写和类型，不接收未声明参数。

不需要改 `building_entry_layer.gd` 或窗口管理。颜色、渐入/渐出时长仍由 entries.style 管；内边宽度等由蒙版生成决定，不能假装仅改shader数值就能重建轮廓。parameters当前支持有限数值、布尔及2/3/4维向量；额外纹理、矩阵等复杂输入需要显式扩展绑定契约，不静默接受。

### 光源呼吸／闪烁

编辑 effect_profile.lights，例如：
```json
{
  "research": {"mode":"breathe", "minimum":0.2, "maximum":1.25, "period_seconds":3.0, "phase":0.0}
}
```

调用同义入口 `host.effects.set_light_behavior("research",参数对象)`。mode支持 `steady/breathe/flicker/off`；steady使用maximum作为常数；空组为1倍。phase单位是周期，不是弧度。强度在0～8倍内，minimum≤maximum，周期为0.05～3600秒。

`local_group_energy`、`emission_group_energy`、`halo_group_energy`始终使用同一倍率，因此不是只让门前光斑变化、窗户留在原地。日周期只控制基准光色，不能写入这三个倍率；提交顺序不会把呼吸状态清掉。flicker由有限谐波产生，可回放，不逐帧随机。

**现有空间数据是四组RGBA：home/library/shop/research。**本轮没有凭空拆出每一盏灯；船舱与灯塔不属于这四组。需要单独控制某一扇窗、新增独立光源或改变受光范围时，仍需重建/发布相应技术资产并扩展通道约定，不能宣称只写任意名字就生效。

### 水面换动效或独立改速度

编辑 effect_profile.water，例如：
```json
{"pattern":"ripples", "period_seconds":2.0, "ripple_spacing":21.0, "ripple_center":[1480.0,340.0]}
```

调用同义入口 `host.effects.set_water_effect(参数对象)`。支持 `drift`（原表现）、`ripples`（径向波纹示例）、`still`（停止水面位移与亮纹）。period仅改变水面，不改变船/旗/风相位。未指定period时沿用现有motion.loop_seconds；未指定phase_radians时沿用原相位偏置。

普通幅度、亮纹强度、原波长与夜间权重仍在 motion.water；接触水线仍在 motion.contact，二者与表面算法不是同一项。水域/岸线遮罩继续来自已通过的港口资产。

新算法只扩展 `water_surface.gdshaderinc` 的 `water_surface_offset(point,lengths)` 和 `water_surface_shimmer(point)`，以及 `water_effect.gd` 的映射/参数绑定。位移须保持单位向量量级，由现有幅度及水域权重约束；不复制船体合成或补底逻辑。

## 2｜每个环节的参数、方法与生效条件

| 环节 | 权威配置／方法 | 何时生效 |
|---|---|---|
| 母图、区域、基础明暗、法线 | 制作目录scene_config.json → base_maps.build | 改结构/法线需重建基础贴图及依赖，再发布 |
| 地面组织、窗洞、静态光晕范围 | 制作目录finish_config.json → ground_emitters.build | 改范围重建；运行整体权重仍由时态uniform控制 |
| 光源位置、距离衰减、接收范围 | 制作目录attenuation_config.json → light_field.build | 重建RGBA32F场再发布；不改母图 |
| 呼吸／闪烁倍率 | effect_profile.lights → light_behavior.set_elapsed | 即时方法或显式重载，不烘焙 |
| 24小时色温／窗灯基准 | daily_cycle.json → menu_clock/daily_cycle → host.apply_uniforms | 启动/时钟configure；预览用set_preview_hour，不改系统时间 |
| Hover算法、算法参数 | effect_profile.hover → entry_highlight.prepare/install | 即时方法或重载；不重建命中 |
| Hover色彩/渐变时长、命中和标签 | entries.json → entry_highlight / building_entry_layer | 当前基本配置在菜单进入时读；几何/内边蒙版变化还要重建entry_assets |
| 水面算法与独立周期 | effect_profile.water → water_effect → water_surface include | 即时方法或重载；保持船的phase |
| 水面幅度/原波长/开关、船体浮动 | motion.json → host.apply_motion/set_elapsed | 菜单进入读配置；程序可更新motion后apply_motion，仍受运动包络约束 |
| 树冠、遮阳棚、旗帜风场 | wind.json → wind_layer.configure/set_elapsed/set_enabled | 普通参数无需烘焙，但当前配置在进入时读取；实时开关已独立 |
| 布料固定端、部件透明度、补底、可动区域 | harbor_layout/wind_layout → harbor_assets/wind_assets | 重建对应资产；不能用扩大幅度代替补底审查 |
| 真实档案UI与功能台位置 | ui_layout → Profile/Console/Dialogs | 菜单创建时读取；不烘焙进背景 |
| 功能权限与进入 | AdventureToolbar.feature_status/request_feature | 读取真实业务/档案；不由视觉参数伪造解锁 |
| 运行发布 | menu.py publish-runtime → runtime_assets → 原生res | 显式发布，不把制作预览自动覆盖到正式资源 |
| 预览与证据 | menu.py effects-preview / runtime-preview | 实际运行与输出；不是仅检查JSON文件存在 |

**可调不等于所有字段都能在同一帧热更新。**表中已区分即时调用、重进菜单、重建技术资产和重新发布。当前没有通用后处理节点图、任意光源自动分组或全景三维重建，新的算法仍需实现它自己的效果文件。

## 3｜时间、提交与校验约定

- 效果使用宿主传入的动作秒数：`set_elapsed(seconds)`或`set_phase(phase)`。不依赖引擎全局TIME、本机日期或每帧随机，因此暂停、回放和时钟调整不破坏动作。
- `apply_profile()`先完成三项验证与hover候选材质准备，再一起提交。未知字段/材质uniform、错误类型、非法灯组、无效灯光或水面周期等返回明确error；原配置、材质和过渡保持有效。
- 正式运行效果以effect_profile为准；素材、31份原生纹理和正式存档不修改。强呼吸、闪烁与同心波示例仅存在制作目录或当前演示实例中。
- 日周期参数也按实际relight声明检查；water_time_gain显式分流到港口材质，不再向光照材质写一个不存在的字段。调制倍率有独立所有者，拒绝被日周期字段覆盖。
- `effect_profile.json`列入 runtime_inputs.json 的 runtime_owned_configs，与daily_cycle/ui_layout一样不会被旧制作目录的归档覆盖。
- 参数类型来自Godot Shader.get_shader_uniform_list；该检验不代表自动理解任意自定义shader的全部视觉语义，特殊数值范围仍需由新效果负责。

## 4｜扩展点与维护规则

`effect_controls.gd`只负责三个效果的验证/事务提交与时间分发，不处理玩家、资源解锁或点击。`effect_uniforms.gd`负责真实材质契约；`light_behavior.gd`负责四组倍率；`water_effect.gd`负责水面算法参数与周期。实例不反向持有宿主，避免引用环。

不要重新把水公式塞回船体变换块，也不要为了新增hover效果复制输入控制器。制作端继续继承正式运行组件，不维护第二份效果算法。

## 5｜本轮证据与交付边界

交付工作目录：`C:\Dev\Tools\ArtControl\runs\main-menu-effects-access-20261112`。

已用正式宿主在无autoload空工程实际运行：经典hover→扫光替换、研究室呼吸及闪烁、水面drift→ripples及独立速度、错误输入拒绝、文件重载回到默认。默认昼夜/hover与修改前截图比较：夜间完全一致，白天最大差1/255且仅1像素，属于本次shader运算路径的量化差异，不能写成全图逐位相同。

呼吸采样的研究室倍率为0.15→0.8→1.45→0.8→0.15，窗口/受光/光晕一致，其他三组保持1。改变水面周期时船phase仍为0.25。上述为2026-11-12中性配置的接口核对记录；2026-11-13默认表现调整见运行管线第9节，不沿用旧像素一致性结论。

证据文件：reports/effect_reachability.json、default_identity.json，以及examples/真实截图与frames/实际视频源帧。按AGENTS没有新增/运行游戏测试套件；本轮是接口/材质接入与实际输出核对，不是全游戏回归或完整发布包验收。

## 技术依据

Godot官方：Shader.get_shader_uniform_list 与 ShaderMaterial 参数绑定；CanvasItem TIME 的行为说明。本实现使用显式动作时间而非内置TIME。
https://docs.godotengine.org/en/stable/classes/class_shader.html
https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html

录制工具曾在等待自动重绘时出现长暂停；当前 effects-preview 使用主线程显式驱动离屏GPU绘制，再读取真实视口图像，已完成整轮重录。该方式仅用于隔离录制，正式菜单不会关闭或接管引擎渲染循环。打包后的res资源不保证可直接编辑：源工程修改配置后重新发布，或由调用代码在内存中应用配置；本轮未增加玩家mod系统。
