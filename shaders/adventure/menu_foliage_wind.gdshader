shader_type canvas_item;

// Coordinates are the original 840x320 hand-painted, transparent canopy artwork.
uniform vec2 artwork_pixels = vec2(840.0, 320.0);
uniform float amplitude_pixels : hint_range(0.0, 24.0) = 14.0;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.0;
uniform float wind_time = 0.0;
varying vec4 tint;

void vertex() {
    tint = COLOR;
}

void fragment() {
    vec2 source_uv = UV;
    if (wind_strength > 0.001) {
        vec2 p = UV * artwork_pixels;
        float t = wind_time;
        // Smooth spatial weights avoid visible seams between adjacent crown groups.
        vec4 zone = vec4(
            exp(-pow((p.x - 105.0) / 190.0, 2.0)),
            exp(-pow((p.x - 310.0) / 165.0, 2.0)),
            exp(-pow((p.x - 505.0) / 165.0, 2.0)),
            exp(-pow((p.x - 710.0) / 175.0, 2.0))
        );
        vec4 phases = vec4(
            sin(t * 1.20 + 0.6),
            sin(t * 1.32 + 1.9),
            sin(t * 1.10 + 2.7),
            sin(t * 1.42 + 3.4)
        );
        float sway = dot(zone, phases) / max(dot(zone, vec4(1.0)), 0.001);
        // Root/wood side remains restrained; exposed edge responds to gusts.
        float outer = 1.0 - smoothstep(35.0, 245.0, p.y);
        float flex = mix(0.2, 1.0, outer);
        float ruffle = sin(t * 2.15 + p.x * 0.021 + p.y * 0.01);
        vec2 offset = vec2(
            (sway + ruffle * 0.16) * amplitude_pixels * flex,
            (sin(t * 1.33 + p.x * 0.016) * 0.21) * amplitude_pixels * flex
        ) * wind_strength;
        source_uv -= offset / artwork_pixels;
    }
    if (any(lessThan(source_uv, vec2(0.0))) ||
        any(greaterThan(source_uv, vec2(1.0)))) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE, source_uv) * tint;
    }
}
