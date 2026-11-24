# 开发与构建

## 首次检出

使用 Git、Godot 4.7.2 stable 标准版（`ed1daf0bf`）和 Python 3.12。游戏使用 GL Compatibility。引擎与素材包路径由调用者提供。

本地 `PVZ-Adventure-local-assets.zip` 补齐原版贴图、声音、字体、制作动画和第四关的三首曲目。整备使用的 ZIP SHA256 为 `2ee86bbd50143ac8578fdc9d56b2329e64b2e714aa50f05eef6232f0c7749427`。包内清单记录相对路径、字节数与 SHA256。原版素材和字体通过有使用权限的本地来源准备。 这里记录的本地素材包基于 v1.0.x。构建 v1.1.3 时，还需补齐本版本引用的冒险运行素材，再执行 Godot 导入。

在仓库根运行以下 PowerShell 命令。

```powershell
$godot = 'C:/path/to/Godot_v4.7.2-stable_win64.exe'
$assets = 'C:/path/to/PVZ-Adventure-local-assets.zip'
python tools/release/restore_assets.py $assets
if ($LASTEXITCODE) { throw '素材还原失败' }

$env:APPDATA = (New-Item -ItemType Directory -Force .release/editor-profile).FullName
$root = (Get-Location).Path
$arguments = @('--headless','--path',('"' + $root + '"'),'--import')
$p = Start-Process $godot -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput .release/import.log -RedirectStandardError .release/import-errors.log
if ($p.ExitCode) { throw "导入失败 ($($p.ExitCode))" }
```

导入后查看两份日志中的资源、脚本和 UID 诊断。也可以在编辑器打开 `project.godot` 后按 F5，通过 Bootstrap 进入海滨菜单。改动卡牌总览或逐卡场景后运行 `python tools/card_catalog.py` 更新清单，再运行 `python tools/card_catalog.py --check` 核对。APPDATA 设置仅影响当前终端及其子进程。

## 测试

```powershell
python tools/release/run_tests.py $godot
python tools/release/run_tests.py $godot test_water_surface_integration test_white_duke_runtime test_adventure_persistence_core
```

用例入口是 `tests/adventure/*.tscn`。每例使用隔离 APPDATA，需要截图和鼠标的用例使用图形模式。退出码、日志错误和完成标记写入 `.release/tests-*/summary.json`。打印了 PASS 后仍出现的错误也记为失败。发布前另用独立解压的 EXE 验证建档、启程、实际种植扣费、返回地图、退出和重开读档。

## Windows x64 发布

PVZ-Adventure 的正式发行使用 `pvz-adventure-v<版本>` 标签。1.0.0 的标签为 `pvz-adventure-v1.0.0`。

从 Godot 模板管理器安装同为 **4.7.2 stable 标准版** 的模板。Windows 模板目录为当前 `APPDATA\Godot\export_templates\4.7.2.stable`，发布版使用 `windows_release_x86_64.exe`。若使用隔离 APPDATA，将模板装到对应目录。 [Godot 4.7.2 官方下载](https://godotengine.org/download/archive/4.7.2-stable/)

```powershell
$out = (New-Item -ItemType Directory -Force .release/windows-x64).FullName
$exe = Join-Path $out 'PVZ-Adventure.exe'
$arguments = @('--headless','--path',('"' + $root + '"'),'--export-release','"Windows Desktop"',('"' + $exe + '"'))
$p = Start-Process $godot -ArgumentList $arguments -Wait -PassThru -RedirectStandardOutput .release/export.log -RedirectStandardError .release/export-errors.log
if ($p.ExitCode) { throw "导出失败 ($($p.ExitCode))" }
Compress-Archive -LiteralPath $exe,(Join-Path $out 'PVZ-Adventure.pck') -DestinationPath .release/PVZ-Adventure-Windows-x64.zip
Get-FileHash .release/PVZ-Adventure-Windows-x64.zip -Algorithm SHA256
git rev-parse HEAD
```

Windows 预设包含动态加载的资源、JSON 和 Shader include，排除编辑器工具和测试。检查导出日志并记录应用版本、完整提交 SHA、Godot 与模板版本、ZIP SHA256 及实机验收结果。自定义关卡入口读取 EXE 旁 `level_game_para/` 下直接存放的 `.tres`，仓库同名目录提供示例。

提交 Godot 源文件与旁置导入配置及 UID。`.godot/` 由引擎重建，构建产物、日志、测试档案留在忽略目录 `.release/`。
