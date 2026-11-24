// 同一头顶云的战场投影。XY 为影心，Z 为按云体浓度加权的暗度，W 为水平半宽。
uniform vec4 passing_cloud = vec4(0.0);

// 和局内角色环境色取样使用同一椭圆、渐变和色值。
vec3 airship_cloud_light(vec2 point) {
	if (passing_cloud.z <= 0.001) {
		return vec3(1.0);
	}
	vec2 relative = (point - passing_cloud.xy) / vec2(max(passing_cloud.w, 1.0), 353.0);
	float mask = (1.0 - smoothstep(0.20, 1.0, dot(relative, relative))) * passing_cloud.z;
	return mix(vec3(1.0), vec3(0.73, 0.79, 0.87), mask);
}
