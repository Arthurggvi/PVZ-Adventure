uniform sampler2D silhouette_atlas : filter_linear, repeat_disable;
uniform vec2 grid = vec2(16.0, 8.0);

varying flat vec3 shadow_data;
varying vec2 pose_uv;

float silhouette_coverage(vec2 coordinate) {
	vec2 cell = floor(shadow_data.rg * 255.0 + vec2(0.5));
	vec2 border = 0.5 / vec2(48.0, 56.0);
	vec2 safe_uv = clamp(coordinate, border, 1.0 - border);
	return texture(silhouette_atlas, (cell + safe_uv) / grid).a;
}
