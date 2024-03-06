shader_type canvas_item;
render_mode unshaded;
uniform sampler2D heightmap;
uniform float height_scale;
uniform float quad_size;

// Normal map will be one pixel smaller than the heightmap width and height
// It stores the face normals of the heightmap's equivalent faces
// This method is better for triplanar and preserving accurate face normals so no distortion on cliffs etc.
// Smooth shading/per vert normals can be done by taking 4 samples in vertex shader of adjacent faces
// You can just average the 4 normals and it gives you smooth shading which is how 3D modelling programs do it.
// In practice I didn't do this since it looks fine without. Could eventually add that and per tri normals.

#include "TerrainShaderUtils.gdshaderinc"

float get_height(vec2 uv) {
	return sample_middle_of_pixel(heightmap,uv).r * height_scale;
}

void fragment() {
	// Note: Per quad normals but it could be the case the heightmap is erratic and it's not actually a quad, could be 2 stretched triangles
	// But this is a good approximation unless it has bad topology. We could store per tri normals here if we really wanted,
	// making the normal map 2x as wide.
	// From what I can tell average the 2 triangle's normals gets rid of all virtually all distortions on triplanar.
	// Even when it doesn't, seems like you can just crank up the texture size a bit and it works.
	float top_left = get_height(SCREEN_UV);
	float top_right = get_height(SCREEN_UV + vec2(SCREEN_PIXEL_SIZE.x, 0.));
	float bottom_left = get_height(SCREEN_UV + vec2(0., SCREEN_PIXEL_SIZE.y));
	vec3 x_basis_toptri = vec3(quad_size, top_right - top_left, 0.);
	vec3 z_basis_toptri = vec3(0., bottom_left - top_left, -quad_size);
	vec3 y_basis_toptri = cross(x_basis_toptri, z_basis_toptri);
	float bottom_right = get_height(SCREEN_UV + SCREEN_PIXEL_SIZE);
	vec3 x_basis_bottri = vec3(quad_size, bottom_right - bottom_left, 0.);
	vec3 z_basis_bottri = vec3(0., bottom_right - top_right, -quad_size);
	vec3 y_basis_bottri = cross(x_basis_bottri, z_basis_bottri);
	
	vec3 n = normalize((y_basis_toptri + y_basis_bottri) / 2.);
	vec3 packed = pack_normal(n).xyz;
	COLOR = vec4(packed, 1.0);
}
