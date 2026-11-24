shader_type canvas_item;
render_mode unshaded;

// 在既有地形图块中的归一化采样范围；不生成或加载另一套地图缩略图。
uniform vec4 crop_uv = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
    float coverage = 1.0 - smoothstep(0.485, 0.5, length(UV - vec2(0.5)));
    // 地形为无mipmap原生纹理；小图标用像素覆盖内的16次均匀采样压低缩小闪烁。
    vec2 footprint = fwidth(UV) * crop_uv.zw;
    vec2 center = crop_uv.xy + UV * crop_uv.zw;
    vec4 source = vec4(0.0);
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 offset = (vec2(float(x), float(y)) + vec2(0.5)) / 4.0 - vec2(0.5);
            source += texture(TEXTURE, center + offset * footprint);
        }
    }
    source /= 16.0;
    COLOR = vec4(source.rgb, source.a * coverage);
}
