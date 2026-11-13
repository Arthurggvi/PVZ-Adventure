shader_type canvas_item;
render_mode unshaded;
// 高亮在原受光后、既有风/船变换前；内侧暖光跟随原蒙版，不把描边留在静止水面。
// 红通道为建筑内区，绿通道为烘焙好的内边缘；两者均不参与输入命中。
uniform sampler2D entry_mask : filter_linear, repeat_disable;
// 由真实焦点状态驱动的平滑强度，范围通常为 0 至 1。
uniform float strength = 0.0;
// 单调场景时间，暂停与制作回放可重复。
uniform float effect_seconds = 0.0;
// 极低内区提亮，避免整座建筑变成黄色平涂。
uniform float fill_gain = 0.018;
// 主要交互提示集中于原轮廓的内侧。
uniform float inner_edge_gain = 0.22;
// 掠光只轻微改变局部明度，不周期缩放整栋建筑。
uniform float sheen_gain = 0.028;
// 每秒掠过的归一化距离；默认约半分钟一轮。
uniform float sheen_speed = 0.035;
// 可用或锁定的实际状态色，由控制器提供。
uniform vec3 accent = vec3(1.0,0.83,0.51);

// 保留原画受光与纹理，只叠加窄内缘及低强度定向掠光。
void fragment() {
    // 前级合成的建筑、水面与灯光颜色。
    vec4 source=texture(TEXTURE,UV);
    if (strength<=0.0) {
        COLOR=source;
    } else {
        // 同一静态形状同时限定内区与内边缘，掠光不会溢出建筑。
        vec2 shape=texture(entry_mask,UV).rg;
        // 斜向窄带在显式场景时间中缓慢移动，避免整块高亮呼吸闪烁。
        float phase=fract(UV.x*0.72+UV.y*0.31-effect_seconds*sheen_speed);
        // 柔化窄带两边，静止画面不会产生硬扫光条。
        float sheen=1.0-smoothstep(0.012,0.095,abs(phase-0.5));
        // 高处边缘略亮，保留一侧受光的温和方向性。
        float direction=0.78+0.22*(1.0-UV.y);
        // 小面积内缘为主要提示，低强度填光仅帮助深色建筑辨识。
        float light=(shape.r*(fill_gain+sheen*sheen_gain)+shape.g*inner_edge_gain*direction)*strength;
        COLOR=vec4(source.rgb+(vec3(1.0)-source.rgb)*accent*light,source.a);
    }
}
