shader_type canvas_item;

// Only the transparent leaf texture moves; the trunk and cloud/background pixels stay static.
uniform bool wind_enabled = false;
uniform vec2 artwork_pixels = vec2(840.0, 320.0);
uniform float amplitude_pixels : hint_range(0.0, 9.0) = 4.6;
varying vec4 tint;

void vertex() {
    tint = COLOR;
}

void fragment() {
    vec2 shifted_uv = UV;
    if (wind_enabled) {
        vec2 p = UV * artwork_pixels;
        float t = TIME;
        // Continuous, overlapping wind zones avoid hard cut lines across the canopy.
        vec4 zone = vec4(
            exp(-pow((p.x - 95.0) / 185.0, 2.0)),
            exp(-pow((p.x - 295.0) / 150.0, 2.0)),
            exp(-pow((p.x - 485.0) / 150.0, 2.0)),
            exp(-pow((p.x - 675.0) / 175.0, 2.0))
        );
        vec4 phases = vec4(
            sin(t * 0.84 + 0.1),
            sin(t * 0.69 + 1.3),
            sin(t * 0.76 + 2.5),
            sin(t * 0.58 + 3.4)
        );
        float sway = dot(zone, phases) / max(dot(zone, vec4(1.0)), 0.001);
        // The wood-side and low foliage moves less; exposed outer leaves move more.
        float tip = mix(0.25, 1.0, 1.0 - smoothstep(80.0, 255.0, p.y));
        float gust = 0.79 + 0.21 * sin(t * 0.23 + 0.7);
        vec2 offset_pixels = amplitude_pixels * tip * gust * vec2(
            sway + 0.13 * sin(t * 1.47 + p.x * 0.013),
            0.29 * sin(t * 0.72 + p.x * 0.009 + 0.8)
        );
        shifted_uv -= offset_pixels / artwork_pixels;
    }
    if (any(lessThan(shifted_uv, vec2(0.0))) ||
        any(greaterThan(shifted_uv, vec2(1.0)))) {
        COLOR = vec4(0.0);
    } else {
        COLOR = texture(TEXTURE, shifted_uv) * tint;
    }
}
