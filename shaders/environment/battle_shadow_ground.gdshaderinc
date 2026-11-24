// 每行一个 MultiMesh 实例。纹理内容为世界坐标、虚拟高度和各灯格映射。
uniform sampler2D projector_instances : filter_nearest, repeat_disable;
uniform vec2 horizontal_ground_axis = vec2(1.0, 0.22);

struct GroundVertex {
	vec2 position;
	vec2 pose_uv;
	vec2 lamp_uv;
	float penumbra_texels;
};

GroundVertex project_ground_vertex(int instance_id, vec2 uv) {
	vec4 pose = texelFetch(projector_instances, ivec2(0, instance_id), 0);
	vec4 ground = texelFetch(projector_instances, ivec2(1, instance_id), 0);
	vec4 emitter = texelFetch(projector_instances, ivec2(2, instance_id), 0);
	float source_radius = texelFetch(projector_instances, ivec2(3, instance_id), 0).r;
	// 倒数第二行严格落于脚点高度。脚线之下只对应地面，不沿射线外推。
	float foot_v = clamp(-pose.y / pose.w, 0.0, 1.0);
	float v = mix(0.0, foot_v, min(uv.y / 0.9, 1.0)) + (1.0 - foot_v) * max((uv.y - 0.9) / 0.1, 0.0);
	vec2 local = pose.xy + vec2(uv.x, v) * pose.zw;
	vec2 point = horizontal_ground_axis * local.x;
	float h = clamp(-local.y * ground.z, 0.0, ground.w);
	float ratio = h / (emitter.z - h);

	GroundVertex result;
	// 相对脚点的 S = P + h/(H-h)·(P-L)。由 MultiMesh 的模型变换统一进灯格。
	result.position = point + ratio * (point + ground.xy);
	result.pose_uv = vec2(uv.x, v);
	result.lamp_uv = (result.position + emitter.xy) / (2.0 * emitter.w) + vec2(0.5);
	result.penumbra_texels = source_radius * ratio * 48.0 / (pose.z * (1.0 + ratio));
	return result;
}
