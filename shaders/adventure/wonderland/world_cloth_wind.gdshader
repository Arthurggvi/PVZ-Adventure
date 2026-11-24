// 布料变形只使用宿主提交的显式相位；暂停时保留已提交的姿态。
shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/ui/main_menu/wind_field.gdshaderinc"
// 独立布料周期换算后的弧度相位，不读取内置TIME。
uniform float cloth_angle = 0.0;
// 最大位移为当前PNG纹理像素，CPU按变形方向的纹理密度换算世界幅度。
uniform float amplitude_px = 4.0;
// false为旗帜左侧固定，true为塔架布幔斜向上缘固定。
uniform bool angled_pin = false;
// 固定边起点按高清PNG自身的局部像素坐标传入。
uniform vec2 pin_a_px = vec2(0.0,0.0);
// 固定边终点与起点使用相同纹理坐标系。
uniform vec2 pin_b_px = vec2(0.0,0.0);
// 固定带宽度按固定边法向的实际纹理密度换算。
uniform float pin_band_px = 4.0;
// 从固定带到自由边的响应距离，同样使用法向纹理像素。
uniform float cloth_depth_px = 36.0;
// 每纹理像素的空间弧度，高清后仍保持原世界波长。
uniform float wave_radians_per_px = 0.10;

// 对纹理反向采样，固定带零位移；采样越界时透明，不扩展原分件包络。
void fragment() {
    vec2 pixel = UV / TEXTURE_PIXEL_SIZE; // 当前纹理局部像素坐标。
    float distance_px; // 到固定边的有符号法向纹理距离。
    if (angled_pin) {
        vec2 axis = normalize(pin_b_px-pin_a_px); // 高清纹理中的固定边方向。
        vec2 normal = vec2(-axis.y,axis.x); // 与CPU法向距离换算配对。
        distance_px = dot(pixel-pin_a_px,normal);
    } else {
        distance_px = pixel.x-pin_a_px.x;
    }
    float response = pow(smoothstep(pin_band_px,pin_band_px+cloth_depth_px,distance_px),1.7); // 固定带到自由边逐渐增强。
    float gust = 0.8+0.2*cos(wind_angle); // 与地图植被和雪共用十八秒阵风包络，保留布料自身惯性周期。
    float wave = sin(cloth_angle+distance_px*wave_radians_per_px)*gust; // 时间和空间相位保持确定性，阵风只减弱不扩大原位移上限。
    vec2 shift = angled_pin ? vec2(1.0,0.0) : vec2(0.0,1.0); // 布幔横移、旗帜纵移。
    vec2 sample_uv = UV-shift*TEXTURE_PIXEL_SIZE*amplitude_px*response*wave; // 当前高清纹理的采样坐标。
    if (any(lessThan(sample_uv,vec2(0.0))) || any(greaterThan(sample_uv,vec2(1.0)))) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE,sample_uv);
    }
}
