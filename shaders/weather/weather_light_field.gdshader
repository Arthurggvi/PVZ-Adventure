shader_type canvas_item;
render_mode unshaded;

uniform vec2 output_size = vec2(533.0, 300.0);
uniform vec2 full_view_size = vec2(1066.0, 600.0);
uniform vec4 lights[8]; // xy: screen UV, z: radius px, w: intensity.
uniform vec4 light_colors[8]; // rgb: emission color.
uniform int light_count = 0;
uniform float weather_strength = 1.0;
uniform float clock_seconds = 0.0;

void fragment() {
    vec2 uv = UV;
    vec3 field = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        if (i >= light_count) { break; }
        vec4 source = lights[i];
        vec2 delta_px = (uv - source.xy) * full_view_size;
        float radius = max(source.z, 1.0);
        float d2 = dot(delta_px, delta_px);
        float core = exp(-d2 / (2.0 * radius * radius * 0.13));
        float halo = exp(-d2 / (2.0 * radius * radius * 0.55));
        float glow = 0.49 * core + 0.51 * halo;
        field += light_colors[i].rgb * source.w * glow;
    }
    COLOR = vec4(clamp(field * weather_strength, vec3(0.0), vec3(3.0)), 1.0);
}
