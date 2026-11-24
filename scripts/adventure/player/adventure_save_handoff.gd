## Android 冒险版存档交接：游戏自持文件，主动授予助手一次只读访问权。
extends RefCounted
class_name AdventureSaveHandoff

## 游戏正式 APK 内已注册的 AndroidX FileProvider，不新增 Provider 或系统权限。
const FILE_PROVIDER: String = "io.github.arthurggvi.pvzadventure.fileprovider"
## 仅允许接收原始存档的助手包名。
const COMPANION_PACKAGE: String = "io.github.arthurggvi.pvzsaveinspector"
## 仅允许助手主界面处理存档，防止系统选择错误 PVZ 改版。
const COMPANION_ACTIVITY: String = COMPANION_PACKAGE + ".MainActivity"
## 从助手 APK 的签名证书取得的 SHA-256 摘要，不是存档哈希。
const COMPANION_CERT: String = "11e7918022190ed8c0d8abdf9998f8f3daf233ee204b57ea932482d6da096899"
## 与助手约定的唯一交接动作。
const TRANSFER_ACTION: String = COMPANION_PACKAGE + ".SAVE_READY"
## 请求口令只允许由助手在本次启动中生成，阻止重复处理旧 Intent。
const REQUEST_NONCE: String = "pvz_adventure_save_nonce"

## 写入当前冒险版的最新状态，返回已提交且属于当前玩家的唯一文件。
static func _save_path() -> String:
	if Global.save_service == null:
		return ""
	return Global.save_service.prepare_current_export_path() # 与原样导出共用事务入口。

## Android 9 及以上调用系统证书核验，避免仿冒包名的助手获得玩家文件。
static func _trusted_companion(activity: Variant) -> bool:
	var Version = JavaClassWrapper.wrap("android.os.Build$VERSION") # Android 版本号。
	if Version.SDK_INT < 28:
		return false
	var pm = activity.getPackageManager() # 精确包名查询，不请求全设备软件列表。
	var expected: PackedByteArray = COMPANION_CERT.hex_decode() # 证书 SHA-256 原始 32 字节。
	var certified: bool = pm.hasSigningCertificate(COMPANION_PACKAGE, expected, 1) # CERT_INPUT_SHA256。
	return certified and JavaClassWrapper.get_exception() == null

## 读取从助手启动游戏时附带的一次性口令，并在成功交接后清除。
## 游戏自启动或旧版助手打开时不触发任何文件操作。
static func maybe_complete_auto_request() -> void:
	if not OS.has_feature("android") or Global.save_service == null \
			or not Global.save_service.is_current_profile_loaded():
		return
	var runtime = Engine.get_singleton("AndroidRuntime") # Godot 自带的 Android Activity 门面。
	if runtime == null:
		return
	var activity = runtime.getActivity() # 仅当前应用的实例。
	var incoming = activity.getIntent() if activity != null else null # 外部启动时附带的请求。
	if incoming == null:
		return
	var nonce: String = str(incoming.getStringExtra(REQUEST_NONCE)) # 口令不来自玩家存档。
	if not _is_nonce(nonce):
		return
	var result: String = send_to_companion(nonce) # 成功后清除，避免界面恢复时重复分享。
	if result.is_empty():
		incoming.removeExtra(REQUEST_NONCE)

## 接受符合 UUID 形式的短期交接口令；空值只允许游戏内的手动按钮。
static func _is_nonce(value: String) -> bool:
	if value.length() != 36:
		return false
	for index: int in range(value.length()): # 必须符合 UUID 的固定连字符位置。
		var character: String = value[index] # 当轮 ASCII 字符。
		if index in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif character not in "0123456789abcdef":
			return false
	return true

## 交接当前玩家正式存档；空 [param nonce] 表示玩家自己从游戏设置页点击发送。
## 返回空字符串代表已成功发起交接，否则返回一条简短反馈。
static func send_to_companion(nonce: String = "") -> String:
	if not OS.has_feature("android"):
		return "仅在安卓游戏内使用。"
	if not nonce.is_empty() and not _is_nonce(nonce):
		return "读取请求无效，请重试。"
	var runtime = Engine.get_singleton("AndroidRuntime") # Godot 内置桥接，不新增第三方插件。
	if runtime == null:
		return "无法连接安卓系统。"
	var activity = runtime.getActivity() # 当前正式游戏的 Activity。
	if activity == null or not _trusted_companion(activity):
		return "请先安装新版存档助手。"
	var path: String = _save_path() # 在生成临时授权前确认当前玩家存档已成功保存。
	if path.is_empty():
		return "请先进入有效存档，再重试。"
	var FileProvider = JavaClassWrapper.wrap("androidx.core.content.FileProvider") # 游戏 APK 已附带。
	var File = JavaClassWrapper.wrap("java.io.File") # 只引用上面的唯一正式存档路径。
	var original = File.File(path) # 不修改原始数据，不生成公共目录副本。
	var uri = FileProvider.getUriForFile(activity, FILE_PROVIDER, original) # 唯一可读内容。
	if uri == null or JavaClassWrapper.get_exception() != null:
		return "无法准备存档，请重试。"
	var Intent = JavaClassWrapper.wrap("android.content.Intent") # Android 显式目标传输。
	var ClipData = JavaClassWrapper.wrap("android.content.ClipData") # 明确附加 URI 读取授权。
	var outgoing = Intent.Intent() # 只会发送到我们签过名的助手主界面。
	outgoing.setAction(TRANSFER_ACTION)
	outgoing.setClassName(COMPANION_PACKAGE, COMPANION_ACTIVITY)
	outgoing.setDataAndType(uri, "application/json")
	outgoing.setClipData(ClipData.newRawUri("PVZAdventureSave", uri))
	outgoing.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_CLEAR_TOP \
		| Intent.FLAG_ACTIVITY_SINGLE_TOP)
	outgoing.putExtra(REQUEST_NONCE, nonce)
	activity.startActivity(outgoing)
	if JavaClassWrapper.get_exception() != null:
		return "无法打开存档助手。"
	return ""
