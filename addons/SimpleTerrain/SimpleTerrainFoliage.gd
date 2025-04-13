@tool
class_name SimpleTerrainFoliage
extends MultiMeshInstance3D

@export var foliage_mesh: Mesh:
	set(value):
		foliage_mesh = value
		_update_multimesh()
		update_configuration_warning()

@export_range(0.1, 10.0) var instance_scale: float = 1.0:
	set(value):
		instance_scale = value
		_update_transforms()

## How much the foliage should be offset from the terrain along the Y axis.
@export var height_offset: float = 0.0:
	set(value):
		height_offset = value

# Keep track of instance count for debugging
var _instance_count_debug := 0

func _ready():
	if Engine.is_editor_hint():
		# Initialize editor-specific functionality here
		_setup_multimesh()
	else:
		# Initialize game-specific functionality here
		pass

func _setup_multimesh():
	if not multimesh:
		_update_multimesh()

func _update_multimesh():
	# Only run in the editor
	if not Engine.is_editor_hint():
		return

	# If multimesh doesn't exist, do nothing. Creation handled by decal.
	if not multimesh:
		return

	var mesh_changed = false

	# Check and assign foliage_mesh if needed
	if foliage_mesh:
		# Only update if the mesh is different
		if multimesh.mesh != foliage_mesh:
			multimesh.mesh = foliage_mesh
			mesh_changed = true
			print("Assigned foliage_mesh to MultiMesh")
	# Handle case where foliage_mesh was removed
	elif multimesh.mesh != null:
		multimesh.mesh = null
		mesh_changed = true
		print("Cleared mesh from MultiMesh as foliage_mesh is null")

	# Update warning only if something actually changed
	if mesh_changed:
		update_configuration_warning()

# Force update of editor warnings
func update_configuration_warning():
	if Engine.is_editor_hint() and is_inside_tree():
		# This tells the editor to refresh the node's warnings
		notify_property_list_changed()

func _update_transforms():
	if not is_inside_tree() or not Engine.is_editor_hint() or not multimesh:
		return
		
	var instance_count = multimesh.visible_instance_count
	#print("Updating scale for %d instances to %f" % [instance_count, instance_scale])
	
	# Update scale of all instances locally
	for i in range(instance_count):
		var current_transform : Transform3D = multimesh.get_instance_transform(i)
		var origin : Vector3 = current_transform.origin
		# Get the rotation part of the basis, ignoring existing scale
		var rotation_quat : Quaternion = current_transform.basis.get_rotation_quaternion()

		# Create a new basis scaled correctly
		# Start with the rotation, then apply the desired uniform scale
		var new_basis : Basis = Basis(rotation_quat).scaled(Vector3(instance_scale, instance_scale, instance_scale))

		# Construct the new transform using the new basis and original origin
		var new_transform : Transform3D = Transform3D(new_basis, origin)
		
		multimesh.set_instance_transform(i, new_transform)

func add_instance_at_position(position: Vector3, random_rotation: bool = true) -> Transform3D:
	# Safety check: Caller (Decal) is responsible for ensuring multimesh exists
	if not multimesh or not foliage_mesh:
		print("ERROR: add_instance_at_position called but multimesh or foliage_mesh is null!")
		return Transform3D.IDENTITY
	
	var current_visible_count = multimesh.visible_instance_count
	_instance_count_debug = current_visible_count
	
	# Ensure we have capacity - grow multimesh as needed
	if current_visible_count >= multimesh.instance_count:
		var new_count = max(100, multimesh.instance_count * 2)
		#print("Growing multimesh: ", multimesh.instance_count, " -> ", new_count)
		
		# 1. Store existing transforms
		var existing_transforms: Array[Transform3D] = []
		for i in range(current_visible_count):
			existing_transforms.append(multimesh.get_instance_transform(i))
			
		# 2. Resize the multimesh instance_count (this clears the buffer)
		multimesh.instance_count = new_count
		
		# 3. Restore the saved transforms
		for i in range(current_visible_count):
			multimesh.set_instance_transform(i, existing_transforms[i])
			
		# 4. Restore the visible count (setting instance_count might reset it)
		multimesh.visible_instance_count = current_visible_count

	# Create transform for the new instance
	var transform = Transform3D.IDENTITY
	
	if random_rotation:
		# Random rotation around Y axis
		transform = transform.rotated(Vector3.UP, randf() * TAU)
		
	# Apply scale (Apply scale *after* rotation)
	transform = transform.scaled(Vector3(instance_scale, instance_scale, instance_scale))

	# Apply translation
	transform.origin = position
	
	# Set the transform for the new instance at the next available index
	multimesh.set_instance_transform(current_visible_count, transform)
	
	# Increase visible count AFTER setting transform
	multimesh.visible_instance_count = current_visible_count + 1
	
	print("Added instance with transform: ", transform, 
		  ", new visible_instance_count: ", multimesh.visible_instance_count)
	
	return transform

# Add multiple instances at once using pre-defined transforms
func add_instances_bulk(transforms_to_add: Array[Transform3D]):
	if not multimesh or not foliage_mesh:
		print("ERROR: add_instances_bulk called but multimesh or foliage_mesh is null!")
		return
	
	if transforms_to_add.is_empty():
		return # Nothing to add

	var current_visible_count = multimesh.visible_instance_count
	var num_to_add = transforms_to_add.size()
	var required_instance_count = current_visible_count + num_to_add

	# --- Resize if needed (only once) --- 
	if required_instance_count > multimesh.instance_count:
		# Calculate new size, ensuring it fits needed instances, grows reasonably
		var new_count = max(required_instance_count, multimesh.instance_count * 2) 
		new_count = max(new_count, 100) # Ensure a minimum size
		#print("Bulk Add: Growing multimesh: ", multimesh.instance_count, " -> ", new_count)
		
		# Store existing transforms before resize clears buffer
		var existing_transforms: Array[Transform3D] = []
		for i in range(current_visible_count):
			existing_transforms.append(multimesh.get_instance_transform(i))
		
		# Resize (clears buffer)
		multimesh.instance_count = new_count
		
		# Restore existing transforms
		for i in range(current_visible_count):
			multimesh.set_instance_transform(i, existing_transforms[i])
		
		# IMPORTANT: Restore visible count to state before adding new ones
		multimesh.visible_instance_count = current_visible_count 
	# --- End Resize --- 

	# --- Add new transforms --- 
	for i in range(num_to_add):
		var target_index = current_visible_count + i
		# Basic safety check, though resizing should prevent this
		if target_index < multimesh.instance_count:
			multimesh.set_instance_transform(target_index, transforms_to_add[i])
		else:
			printerr("Bulk Add Error: Target index out of bounds after resize! Index: ", target_index, ", Instance Count: ", multimesh.instance_count)
	# --- End Add new transforms --- 

	# --- Update visible count once --- 
	multimesh.visible_instance_count = required_instance_count
	#print("Bulk Add: Added ", num_to_add, " instances. New visible count: ", multimesh.visible_instance_count)

# Add an instance using a pre-defined transform (used for redo)
func add_instance_with_transform(transform: Transform3D):
	# Safety check: Caller (Decal) is responsible for ensuring multimesh exists
	if not multimesh or not foliage_mesh:
		print("ERROR: add_instance_with_transform called but multimesh or foliage_mesh is null!")
		return

	var current_visible_count = multimesh.visible_instance_count

	# Ensure capacity (same logic as add_instance_at_position)
	if current_visible_count >= multimesh.instance_count:
		var new_count = max(100, multimesh.instance_count * 2)
		#print("Growing multimesh for redo: ", multimesh.instance_count, " -> ", new_count)
		var existing_transforms: Array[Transform3D] = []
		for i in range(current_visible_count):
			existing_transforms.append(multimesh.get_instance_transform(i))
		multimesh.instance_count = new_count
		for i in range(current_visible_count):
			multimesh.set_instance_transform(i, existing_transforms[i])
		multimesh.visible_instance_count = current_visible_count

	# Set the provided transform at the next available index
	multimesh.set_instance_transform(current_visible_count, transform)

	# Increase visible count
	multimesh.visible_instance_count = current_visible_count + 1

	#print("Redo: Added instance with transform: ", transform,
	#	  ", new visible_instance_count: ", multimesh.visible_instance_count)

func remove_instance(index: int) -> bool:
	if not multimesh:
		return false
		
	var current_count = multimesh.visible_instance_count
	
	if index < 0 or index >= current_count:
		return false
	
	# Move the last instance to the removed spot (unless it's the last one)
	if index < current_count - 1:
		var last_transform = multimesh.get_instance_transform(current_count - 1)
		multimesh.set_instance_transform(index, last_transform)
	
	# Reduce the visible count
	multimesh.visible_instance_count = current_count - 1
	
	return true

func clear_instances():
	if not multimesh:
		return
		
	multimesh.visible_instance_count = 0
	#print("Cleared all instances")

# Remove all instances after a specific index (used for undo)
func clear_instances_from(start_index: int):
	if not multimesh:
		return
	
	if multimesh.visible_instance_count > start_index:
		#print("Clearing instances from index ", start_index, 
		#	  ", before: ", multimesh.visible_instance_count)
		multimesh.visible_instance_count = start_index
		#print("After clearing: visible_instance_count=", multimesh.visible_instance_count)

# Set the visible instance count directly (used for undo/redo)
func set_visible_instance_count(count: int):
	if not multimesh:
		return
	# Ensure count is valid
	if count >= 0 and count <= multimesh.instance_count:
		multimesh.visible_instance_count = count
		#print("Set visible_instance_count to: ", count)
	else:
		# This might happen if instance_count was reduced unexpectedly
		print("Warning: Invalid count for set_visible_instance_count: ", count, 
			  ", current instance_count: ", multimesh.instance_count, 
			  ", current visible_instance_count: ", multimesh.visible_instance_count)
		# As a fallback, set to the nearest valid boundary
		multimesh.visible_instance_count = clamp(count, 0, multimesh.instance_count)

# Calculate the necessary height updates for all instances based on the parent terrain height.
# Returns an array of changes: [ [index, old_transform, new_transform], ... ]
func update_instance_heights() -> Array:
	var changes : Array = []
	
	if not is_inside_tree() or not Engine.is_editor_hint():
		print("Cannot calculate heights: Not in tree or not in editor.")
		return changes

	var parent = get_parent()
	if not parent is SimpleTerrain:
		print("Cannot calculate heights: Parent is not SimpleTerrain.")
		return changes
		
	if not multimesh:
		print("Cannot calculate heights: MultiMesh is not initialized.")
		return changes

	var instance_count = multimesh.visible_instance_count
	if instance_count == 0:
		# print("No instances to calculate height updates for.")
		return changes

	# print("Calculating height updates for %d instances..." % instance_count)
	# Cache global transform for efficiency
	var foliage_global_transform = global_transform
	# Define a small tolerance for floating point comparisons
	const Y_TOLERANCE = 0.001 
	
	for i in range(instance_count):
		var old_transform = multimesh.get_instance_transform(i)
		
		# Calculate the global position of the instance
		var instance_global_pos : Vector3 = foliage_global_transform * old_transform.origin
		
		# Get the terrain height at the instance's global XZ position
		var terrain_local_y : float = parent.get_real_local_height_at_pos(instance_global_pos, parent.highest_lod_resolution)
		
		# Check if the Y position actually needs changing (within tolerance)
		# Apply the height offset to the target Y
		var target_local_y = terrain_local_y + height_offset
		
		if abs(old_transform.origin.y - target_local_y) > Y_TOLERANCE:
			# Create the new local origin for the instance
			var new_local_origin = Vector3(old_transform.origin.x, target_local_y, old_transform.origin.z)
			
			# Create the new transform, preserving rotation and scale
			var new_transform = Transform3D(old_transform.basis, new_local_origin)
			
			# Add the change to our list
			changes.append([i, old_transform, new_transform])
		
	# print("Finished calculating instance height updates. %d changes needed." % changes.size())
	return changes

func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if not get_parent() is SimpleTerrain:
		warnings.append("SimpleTerrainFoliage must be a child of a SimpleTerrain node to function properly.")
	
	if not foliage_mesh:
		warnings.append("No foliage mesh assigned. Assign a mesh to display foliage.")
	
	return warnings 
