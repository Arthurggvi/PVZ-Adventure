# PVZ-Adventure / 僵尸岛大地图素材 v1.0

## 交付物

- `map/zombie_island_background.png`: 原始1672×941背景，不含标题、文字、关卡路径、固定节点、按钮。
- `map/zombie_island_background_1920x1080.png`: 适合16:9 Godot场景使用的版本。
- `buttons/button_frame_blank.png`: 通用384×384透明PNG按钮边框；中间完全透明。
- `icons/01...06..._icon.png`: 六张独立透明圆形场景缩略图，无文本数字。
- `buttons/01...06..._button.png`: 六张已经把图标和边框组合的透明按钮，适合快速拖入场景。
- `preview/stage_button_placement.jpg`: 六关示意摆放效果，**不是正式地图文件**。
- `preview/six_buttons_transparent.png`: 关卡按钮一览，**不是场景中应加载的图集**。
- `layout.json`: 关卡ID、中文名、贴图相对路径和归一化摆放坐标。

## Godot建议

1. `TextureRect` 展示静态背景，使用16:9适配与容器锚点，不允许背景按钮响应输入。
2. 六个 `TextureButton` 依次载入 `buttons/##_..._button.png`；布局使用 `layout.json` 的归一化中心坐标。
3. 每个按钮的关卡名、关卡编号都使用Godot动态`Label`，不要再写进PNG。
4. 锁定：状态机控制`disabled`，使用独立的遮罩Shader（灰阶+暗化）和Godot绘制的锁图标。解除锁定时恢复原色。
5. 已通关：叠加对勾图标，勿修改原按钮源文件。
6. 选中：用Tween(0.15s)让按钮缩放1.0→1.08；按下回弹1.08→0.94→1.0。
7. 关卡显示与解锁与地图静态美术解耦。**不绘制关卡路线**。
8. 海浪/瀑布可加局部UV流动Shader；下水道加绿色气泡GPU粒子；墓地薄雾使用缓慢滚动透明贴图；神殿紫色光脉冲使用单独的覆盖图和Tween。初期先做按钮反馈，环境动画可后加。
9. 动态僵尸从已存在的PVZ工程`AnimatedSprite2D`或资源系统复用，避免把会移动的僵尸烘焙进背景。

## 美术限制

这个资源包基于生成美术；第一轮应当用作可玩原型。已经检查素材尺寸及PNG alpha；地图文字和路线均未烘焙。按钮采用对应场景的圆形图案缩略图，并非传统文字牌匾。如果后续要采用纯图标风格，可以直接替换`icons/`，保留`button_frame_blank.png`和系统结构。
