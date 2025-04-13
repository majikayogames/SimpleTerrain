shader_type spatial;
//render_mode depth_draw_always; // Needed because we set alpha for holes
render_mode unshaded,wireframe,cull_disabled;

#include "TerrainShaderUtils.gdshaderinc"

uniform sampler2D heightmap;
uniform sampler2D splatmap;
uniform sampler2D normalmap;

uniform bool triplanar_on_texture_0 = true;
uniform bool triplanar_on_texture_1 = false;
uniform bool triplanar_on_texture_2 = false;
uniform bool triplanar_on_texture_3 = false;

uniform sampler2D texture_0_albedo : source_color;
uniform sampler2D texture_1_albedo : source_color;
uniform sampler2D texture_2_albedo : source_color;
uniform sampler2D texture_3_albedo : source_color;

uniform sampler2D texture_0_normal;
uniform sampler2D texture_1_normal;
uniform sampler2D texture_2_normal;
uniform sampler2D texture_3_normal;

uniform vec2 texture_0_uv_scale;
uniform vec2 texture_1_uv_scale;
uniform vec2 texture_2_uv_scale;
uniform vec2 texture_3_uv_scale;

uniform ivec3 cam_chunk_loc;
uniform vec3 cam_rel_pos;
uniform mat3 inv_normal_basis;
uniform mat4 inv_global_transform;
uniform ivec2 chunk_count;
uniform float terrain_xz_scale;
uniform float terrain_height_scale;
uniform int highest_lod_res;
uniform float lod_dropoff_rate;

varying vec3 v_vert_pos_local;
varying vec3 v_normal;
varying vec4 v_splat_color;
varying vec3 v_vert_pos_normalized;

const float NUDGE = 0.00001;

vec4 texture_triplanar_if_enabled(int texture_num, sampler2D tex, vec3 local_pos, vec3 normal, vec2 uv_scale) {
	if((triplanar_on_texture_0 && texture_num == 0) || (triplanar_on_texture_1 && texture_num == 1)
	|| (triplanar_on_texture_2 && texture_num == 2) || (triplanar_on_texture_3 && texture_num == 3)) {
		return texture_triplanar(tex, local_pos, normal, uv_scale);
	}
	else {
		return texture(tex, local_pos.xz / uv_scale);
	}
}

int get_lod(vec3 vert_pos_local) {
	// Find LOD. When at an edge, nudge vert away from camera so it rounds down to the proper chunk.
	vec2 total_terrain_xz_size = terrain_xz_scale * vec2(chunk_count);
	vec3 vert_pos_normalized = vert_pos_local / vec3(total_terrain_xz_size.x, 1., total_terrain_xz_size.y);
	vec3 nudge_edge_verts = sign(vert_pos_local - cam_rel_pos) * NUDGE;

	ivec3 my_chunk_loc = ivec3(v_vert_pos_normalized * vec3(float(chunk_count.x), 1.0, float(chunk_count.y)) + nudge_edge_verts);
	int diff = max(
		max(
			abs(my_chunk_loc.x - cam_chunk_loc.x),
			abs(my_chunk_loc.z - cam_chunk_loc.z)
		),
		abs(my_chunk_loc.y - cam_chunk_loc.y)
	);

	return max(
		0, highest_lod_res - int(lod_dropoff_rate * float(diff))
	);
}

void vertex() {
	// Put vert in world space, then make it relative to the terrain's world start pos.
	vec3 vert_relative_to_terrain = (inv_global_transform * (MODEL_MATRIX * vec4(VERTEX, 1.0))).xyz;
	// Normalize vert between 0 (start of terrain) and 1 (end of terrain).
	vec2 total_terrain_xz_size = terrain_xz_scale * vec2(chunk_count);
	v_vert_pos_normalized = vert_relative_to_terrain / vec3(total_terrain_xz_size.x, 1., total_terrain_xz_size.y);

	int my_lod = get_lod(vert_relative_to_terrain);

	// When next to a lower LOD chunk, snap vert to nearest 2 subdivisions on lower LOD and interpolate.
	// Will have no effect if not on a chunk edge. (When chunk LOD == nudged LOD).
	float num_segments_per_chunk = pow(2.0, float(my_lod));
	vec2 num_segments_total = vec2(chunk_count) * num_segments_per_chunk;
	vec2 subdiv_size_normal = 1.0 / num_segments_total;
	vec2 snap_down = floor(v_vert_pos_normalized.xz * num_segments_total + NUDGE) / num_segments_total;
	vec2 snap_up = ceil(v_vert_pos_normalized.xz * num_segments_total - NUDGE) / num_segments_total;
	vec2 snap_diff = (v_vert_pos_normalized.xz - snap_down) / subdiv_size_normal;
	float interp_factor = max(snap_diff.x, snap_diff.y);

	// Get height at the 2 closest vertices on subdiv and interpolate.
	// snap_up and snap_down will be equal if not stepping down an LOD.
	float heightmap_val = mix(
		sample_middle_of_pixel(heightmap, snap_down).r,
		sample_middle_of_pixel(heightmap, snap_up).r,
		interp_factor
	);
	VERTEX.y = heightmap_val * terrain_height_scale;
	v_vert_pos_local.y = heightmap_val * terrain_height_scale;
	v_vert_pos_local.xz = (v_vert_pos_normalized.xz * vec2(chunk_count) * terrain_xz_scale);

	v_splat_color = sample_middle_of_pixel(splatmap, v_vert_pos_normalized.xz).rgba;
}

void fragment() {
    // Here, each channel of the splatmap directly represents the weight of each texture. Black is texture 0
    float tex_0_weight = clamp(1.0 - (v_splat_color.r + v_splat_color.g + v_splat_color.b), 0., 1.);
    float tex_1_weight = v_splat_color.r; // Weight for red (tex 1)
    float tex_2_weight = v_splat_color.g; // Weight for blue (tex 2)
    float tex_3_weight = v_splat_color.b; // Weight for green (tex 3)

    // Ensure the weights sum up to 1.0
    float total_weight = tex_0_weight + tex_1_weight + tex_2_weight + tex_3_weight;
    tex_0_weight /= total_weight;
    tex_1_weight /= total_weight;
    tex_2_weight /= total_weight;
    tex_3_weight /= total_weight;

	vec3 normal0 = unpack_normal(texture(texture_0_normal, v_vert_pos_local.xz / texture_0_uv_scale));
	vec3 normal1 = unpack_normal(texture(texture_1_normal, v_vert_pos_local.xz / texture_1_uv_scale));
	vec3 normal2 = unpack_normal(texture(texture_2_normal, v_vert_pos_local.xz / texture_2_uv_scale));
	vec3 normal3 = unpack_normal(texture(texture_3_normal, v_vert_pos_local.xz / texture_3_uv_scale));

    // Blend the normal maps in the same way as the textures
    vec3 ground_normal = normal0 * tex_0_weight +
                         normal1 * tex_1_weight +
                         normal2 * tex_2_weight +
                         normal3 * tex_3_weight;

	vec3 terrain_normal = unpack_normal(texture(normalmap, v_vert_pos_normalized.xz));
	vec3 terrain_and_ground_normal = apply_normal_basis(ground_normal, terrain_normal);

	//if (terrain_normal.y < 0.0) {
		//ALBEDO = vec3(1.0,0.0,0.0);
	//}

	// Put in world space
	vec3 terrain_normal_world = normalize(inv_normal_basis * terrain_and_ground_normal);

    // Sample each of the four textures. Only doing triplanar on the first one.
	vec3 tex_0_color = texture_triplanar_if_enabled(0, texture_0_albedo, v_vert_pos_local, terrain_normal, texture_0_uv_scale).rgb;
	vec3 tex_1_color = texture_triplanar_if_enabled(1, texture_1_albedo, v_vert_pos_local, terrain_normal, texture_1_uv_scale).rgb;
	vec3 tex_2_color = texture_triplanar_if_enabled(2, texture_2_albedo, v_vert_pos_local, terrain_normal, texture_2_uv_scale).rgb;
	vec3 tex_3_color = texture_triplanar_if_enabled(3, texture_3_albedo, v_vert_pos_local, terrain_normal, texture_3_uv_scale).rgb;

    // Blend the textures based on the weights
    vec3 final_color = tex_0_color * tex_0_weight +
                       tex_1_color * tex_1_weight +
                       tex_2_color * tex_2_weight +
                       tex_3_color * tex_3_weight;

    // Assign the final color to the fragment's albedo
    ALBEDO = final_color;
	//ALBEDO = vec3(tex_0_weight);
	//ALBEDO = terrain_normal;
	// Only make it a hole if the tri is fully transparent. This is so we have clearly defined holes.
	if (v_splat_color.a < 0.0001) {
		discard;
	}

	NORMAL = (VIEW_MATRIX * (vec4(terrain_normal_world, 0.0))).xyz;

	vec3 chunk_loc = v_vert_pos_normalized * vec3(float(chunk_count.x), 1.0, float(chunk_count.y));
	//if((ivec2(chunk_loc.xz).x + ivec2(chunk_loc.xz).y) % 2 == 0) {
		//ALBEDO = mix(ALBEDO, vec3(1.), 0.25);
	//}
	int chunk_lod = get_lod(v_vert_pos_local);
	float lod_pct = 1.0 - float(chunk_lod) / float(highest_lod_res);
	if((floor(chunk_loc.xz + vec2(NUDGE)) != floor(chunk_loc.xz)) || (floor(chunk_loc.xz - vec2(NUDGE)) != floor(chunk_loc.xz))) {
		int lod_color = highest_lod_res - chunk_lod - 1;
		if(lod_color == -1) {
			ALBEDO = vec3(1.);
		}
		else if(lod_color % 3 == 0) {
			ALBEDO = mix(ALBEDO, vec3(0., 1., 0.), 1.1);
		}
		else if(lod_color % 2 == 0) {
			ALBEDO = mix(ALBEDO, vec3(1., 0., 0.), 1.1);
		}
		else {
			ALBEDO = mix(ALBEDO, vec3(0., 0., 1.), 1.1);
		}
	}
}
