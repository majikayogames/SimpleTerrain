// Unpack from texture -> XYZ. Texture is between 0 and 1, normals are -1 to 1. Negate Z because OpenGL uses Y-up normal maps.
vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

vec4 pack_normal(vec3 n) {
	return vec4((0.5 * (n + 1.0)).xzy, 1.0);
}

// Change of basis https://www.youtube.com/watch?v=P2LTAUO1TdA
vec3 apply_normal_basis(vec3 n1, vec3 n2)
{
	vec3 up = n1;
	vec3 right = vec3(n1.y, -n1.z, n1.x);
	vec3 forward = vec3(n1.x, -n1.z, n1.y);
	vec3 change_of_basis = n2.x*right + n2.y*up + n2.z*forward;
	
	// Prevent n2 rotated from pointing away from n1
	//change_of_basis.y = max(change_of_basis.y, 0.0);
	
    return normalize(change_of_basis);
}

// Function for triplanar texture blending
vec4 texture_triplanar(sampler2D tex, vec3 world_pos, vec3 normal, vec2 uv_scale) {
    // Blend factors based on the normal, abs to ensure positive values
    vec3 blend = abs(normalize(normal));

    // Normalize blend factors to ensure they sum to 1
    blend /= (blend.x + blend.y + blend.z);

    // Smooth the blend factors to reduce artifacts
    float sharpness = 2.0; // Adjust sharpness as needed
    blend = pow(blend, vec3(sharpness));

    // Normalized again after smoothing
    blend /= dot(blend, vec3(1.0));

    // Texturing for each plane
    vec4 texX = texture(tex, world_pos.yz / uv_scale) * blend.x;
    vec4 texY = texture(tex, world_pos.xz / uv_scale) * blend.y;
    vec4 texZ = texture(tex, world_pos.xy / uv_scale) * blend.z;

    // Final color blend
    return texX + texY + texZ;
}

vec4 sample_middle_of_pixel(sampler2D tex, vec2 uv) {
	// Sample from exact middle of each pixel to ensure same result as in collision shape calculation.
	vec2 texture_coords_in_px = floor(uv * (vec2(textureSize(tex, 0)) - 1.0));
	texture_coords_in_px += 0.5;
	
	// Put coordinates back into UV space and sample texture.
	vec2 texture_position = clamp(texture_coords_in_px / vec2(textureSize(tex,0)), 0.0, 1.0);
	return texture(tex, texture_position);
}