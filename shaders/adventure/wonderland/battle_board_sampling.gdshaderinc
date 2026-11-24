// 只扩展画面右缘，供原版选卡横移使用；原图范围内的像素和棋盘坐标不变。
uniform float right_extension : hint_range(0.0, 0.5) = 0.0;

// 扩展后的片元仍使用原图比例，保持浪峰与种植行界一致。
vec2 board_art_uv(vec2 uv) {
    return uv * vec2(1.0 + right_extension, 1.0);
}

// 右缘接到同高度的开阔水域；内建 TEXTURE 由片元直接采样，避免导出时丢失采样器绑定。
vec2 board_art_continuation_uv(vec2 uv) {
    return vec2(0.42 + uv.x - 1.0, uv.y);
}
