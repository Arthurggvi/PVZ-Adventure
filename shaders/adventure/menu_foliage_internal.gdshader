shader_type canvas_item;

// The original 1920x1080 painting always remains the source of truth.
// Motion is strictly confined to the eroded *interior* of its foliage.
// Never translate the alpha silhouette or alter sky pixels.
uniform sampler2D motion_core : filter_linear, repeat_disable;
uniform vec2 artwork_pixels = vec2(1920.0, 1080.0);
uniform float amplitude_pixels : hint_range(0.0, 12.0) = 7.0;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.0;
uniform float wind_time = 0.0;
varying vec4 tint;

void vertex() {
    tint = COLOR;
}

void fragment() {
    vec4 original = texture(TEXTURE, UV);
    float weight = texture(motion_core, UV).r;
    if (wind_strength > 0.001 && weight > 0.001) {
        vec2 pixel = UV * artwork_pixels;
        float t = wind_time;
        float slow = sin(t * 1.15 + pixel.x * 0.009 + pixel.y * 0.012);
        float flutter = sin(t * 2.24 + pixel.x * 0.024);
        float rise = cos(t * 1.36 + pixel.x * 0.013);
        vec2 shift = amplitude_pixels * wind_strength * vec2(
            0.77 * slow + 0.23 * flutter,
            0.23 * rise
        ) * weight;
        vec2 displaced_uv = clamp(UV + shift / artwork_pixels, vec2(0.0), vec2(1.0));
        // Do not sample outside the same safe interior island.
        float source_weight = texture(motion_core, displaced_uv).r;
        vec4 moving = texture(TEXTURE, displaced_uv);
        COLOR = mix(original, moving, weight * source_weight) * tint;
    } else {
        COLOR = original * tint;
    }
}
