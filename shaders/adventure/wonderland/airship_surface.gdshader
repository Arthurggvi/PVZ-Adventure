// 完整飞艇由原始底图保持，本层仅覆盖内缩安全蒙版内的原图RGB微形变。
shader_type canvas_item;
render_mode unshaded;

// 与原图裁切同尺寸的安全蒙版；外轮廓、孔洞和索具连接处为零，不随时间采样偏移。
uniform sampler2D motion_mask : hint_default_black, filter_linear, repeat_disable;
// 宿主按独立周期计算的显式弧度相位，暂停时保留此值，不使用TIME。
uniform float surface_angle = 0.0;
// 半个世界像素上限按实际x/y纹理密度分别换算后的位移，单位为当前纹理像素。
uniform vec2 amplitude_px = vec2(0.0);
// 一个周期的弧度数，同时用于缓慢变化的空间波形。
const float WAVE_CYCLE = 6.28318530718;
// 双轴各缩到1/sqrt(2)，使世界空间合成位移也不超过配置幅度。
const float AXIS_GAIN = 0.70710678118;

// 只改变RGB采样位置，输出透明度固定取蒙版原位置，禁止移动外轮廓或露出底层信息。
void fragment() {
    float mask = texture(motion_mask, UV).r; // 当前固定安全区域的覆盖强度。
    vec2 wave = vec2(sin(surface_angle+UV.y*WAVE_CYCLE),cos(surface_angle+UV.x*WAVE_CYCLE))*AXIS_GAIN; // 单周期、长度不超过1的内部波形。
    vec2 offset_px = wave*amplitude_px*mask; // 蒙版边缘处位移同步归零，不能把整张裁切图平移。
    vec2 half_texel = TEXTURE_PIXEL_SIZE*0.5; // 限制采样在裁切纹理有效像素中心内。
    vec2 sample_uv = clamp(UV+offset_px*TEXTURE_PIXEL_SIZE,half_texel,vec2(1.0)-half_texel); // 从完整原图RGB取微小偏移后的颜色。
    COLOR = vec4(texture(TEXTURE,sample_uv).rgb,mask);
}
