shader_type canvas_item;
render_mode unshaded;
// 可替换hover示例：沿同一可见蒙版轻扫，不改命中、权限、输入或物件运动。
uniform sampler2D entry_mask : filter_linear, repeat_disable;
uniform float strength = 0.0;
uniform vec3 accent = vec3(1.0,0.86,0.58);
uniform float effect_seconds = 0.0;
uniform float fill_gain = 0.04;
uniform float inner_edge_gain = 0.24;
uniform float sweep_gain = 0.16;
uniform float period_seconds = 2.4;
uniform float band_width = 0.10;
void fragment() {
    vec4 source=texture(TEXTURE,UV);
    vec2 mask=texture(entry_mask,UV).rg;
    float sweep=0.5+0.5*sin((UV.x+UV.y)*9.0-effect_seconds*6.28318530718/max(period_seconds,0.05));
    float band=smoothstep(1.0-clamp(band_width,0.005,1.0),1.0,sweep);
    vec3 fill=source.rgb+(vec3(1.0)-source.rgb)*accent*(fill_gain+sweep_gain*band)*mask.r*strength;
    COLOR=vec4(mix(fill,accent,mask.g*inner_edge_gain*strength),source.a);
}
