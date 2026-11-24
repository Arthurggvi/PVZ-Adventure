## 为全局存档分配稳定编号。存档改名、进度写入和正常备份均保留同一编号。
extends RefCounted
class_name SaveProfileIdentity

## 位于全局存档根，独立于玩家昵称、卡牌 UID 和装备 UID。
const FIELD: String = "profile_uid"
## SHA-256 摘要与新档案随机编号的字节数。
const UID_BYTES: int = 32
## 每个字节编码为两个十六进制字符。
const LENGTH: int = UID_BYTES * 2

## 恢复 [param data] 的编号；没有该字段的旧档使用同一份已读取的 [param source] 字节计算初始编号。
## 损坏编号或无法计算指纹返回空字符串，交给保存服务拒绝加载。
static func resolve(data: Dictionary, source: PackedByteArray) -> String:
	if data.has(FIELD):
		var stored: Variant = data[FIELD] # 已写入的编号优先于当前文件指纹。
		return stored if is_valid(stored) else ""
	var digest := HashingContext.new() # 输入为原始字节，不受 JSON 重排和浮点格式化影响。
	if source.is_empty() or digest.start(HashingContext.HASH_SHA256) != OK or digest.update(source) != OK:
		return ""
	return digest.finish().hex_encode()

## 创建全新玩家档案的编号，不使用昵称、时钟或第一个物品编号。
static func create_uid() -> String:
	return Crypto.new().generate_random_bytes(UID_BYTES).hex_encode()

## [param value] 必须是规范的小写十六进制字符串。
static func is_valid(value: Variant) -> bool:
	if not value is String or value.length() != LENGTH:
		return false
	for character: String in value: # 禁止大小写变体、符号或前缀占用相同逻辑编号。
		if character not in "0123456789abcdef":
			return false
	return true
