@tool
extends Node

func render_normalmap(heightmap : Texture2D, height_scale : float, quad_size : float) -> ViewportTexture:
	$SubViewport/TextureRect.material.set_shader_parameter("heightmap", heightmap)
	$SubViewport/TextureRect.material.set_shader_parameter("height_scale", height_scale)
	$SubViewport/TextureRect.material.set_shader_parameter("quad_size", quad_size)
	#$SubViewport/TextureRect.custom_minimum_size = heightmap.get_size() if heightmap else Vector2i(1,1)
	# It's one less pixel as we are calulcating per quad normals not per vertex normals
	$SubViewport.size = Vector2i(heightmap.get_size() - Vector2(1,1)) if heightmap else Vector2i(1,1)
	$SubViewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return $SubViewport.get_texture()
