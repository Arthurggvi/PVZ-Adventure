shader_type canvas_item;
render_mode unshaded;
// 高亮在原受光后、既有风/船变换前；只用内侧边缘，不把外描边留在静止水面。
uniform sampler2D entry_mask : filter_linear, repeat_disable;
uniform float strength = 0.0;
uniform float effect_seconds = 0.0; // 契约保留：默认效果不依赖时间。
uniform float fill_gain = 0.13;
uniform float inner_edge_gain = 0.34;
uniform vec3 accent = vec3(1.0,0.86,0.58);
void fragment() {
    vec4 source=texture(TEXTURE,UV);
    if (strength<=0.0) {
        COLOR=source;
    } else {
        vec2 shape=texture(entry_mask,UV).rg;
        float mask=shape.r;
        float edge=shape.g;
        vec3 fill=source.rgb+(vec3(1.0)-source.rgb)*accent*fill_gain*mask*strength;
        COLOR=vec4(mix(fill,accent,edge*inner_edge_gain*strength),source.a);
    }
}
