extends Node3D

func _ready() -> void:
	# Verify there are actual trees to process
	if get_child_count() == 0:
		return
		
	# 1. Target the first Final_tree2 instance in your level to capture its data
	var first_tree_instance = get_child(0)
	
	# Reach into the tree instance to find your tree_08 visual sub-scene
	var tree_08_instance = first_tree_instance.get_node_or_null("tree08")
	if not tree_08_instance:
		push_error("Optimization Failed: Could not find a node named 'tree08' inside your tree scene.")
		return
		
	# Reach inside that sub-scene to pull out the raw MeshInstance3D geometry
	var mesh_node = tree_08_instance.get_node_or_null("tree08") as MeshInstance3D
	if not mesh_node or not mesh_node.mesh:
		push_error("Optimization Failed: Could not find the MeshInstance3D asset inside 'tree_08'.")
		return
		
	# 2. Grab the texture/material data!
	# We check the active material on the mesh node surface so the look is preserved
	var active_material = mesh_node.get_active_material(0)
		
	# 3. Build the ultra-fast MultiMesh infrastructure
	var multimesh_instance = MultiMeshInstance3D.new()
	var multimesh = MultiMesh.new()
	
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh_node.mesh
	multimesh.instance_count = get_child_count()
	
	multimesh_instance.multimesh = multimesh
	
	# Fix: Apply the tree's original material/texture to all instances
	if active_material:
		multimesh_instance.material_override = active_material
	
	get_parent().call_deferred("add_child", multimesh_instance)
	
	# 4. Loop through all 5,000 trees to shift their visuals to the GPU batcher
	for i in range(get_child_count()):
		var tree_node = get_child(i)
		
		# Teleport this instance's visual instructions to the master MultiMesh
		multimesh.set_instance_transform(i, tree_node.global_transform)
		
		# Discard the individual 3D model node to save memory and draw calls
		var visual_subscene = tree_node.get_node_or_null("tree08")
		if visual_subscene:
			visual_subscene.queue_free()
			
		# What is left running inside tree_node is strictly its StaticBody3D and CollisionShape3D!
