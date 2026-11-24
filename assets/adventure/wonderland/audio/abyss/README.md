# 深海环境音

本任务原创程序合成，不使用外部采样。2026-11-16。

- `pressure.ogg`：22050 Hz 双声道、24 秒无缝循环。过滤噪声与 91/137/178 Hz 的低幅共鸣；只对此文件启用导入循环。
- `resonance.ogg`：22050 Hz 双声道、9 秒单次远方共鸣。约 107 Hz 的缓慢音高漂移、微弱泛音、宽幅软包络与少量声像变化。
- 使用 NumPy 固定随机种子 `316101` 合成，FFmpeg Vorbis quality 3 编码。两个运行时文件合计 109102 字节。
- 声音由 `BattleEnvironmentAudio` 的 SFX 子总线混合。音量、事件时序及滤波设置见 `docs/adventure/psychedelic_abyss_environment.md`，不参与 BGM。
