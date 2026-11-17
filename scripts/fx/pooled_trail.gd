class_name PooledTrail
extends CPUParticles3D
## Estela de brasas de algo que sale del pool (una pluma ardiente). El pool
## esconde el nodo al guardarlo y lo muestra al reusarlo: la estela arranca
## limpia cada vez que vuelve a verse, así no arrastra las brasas del vuelo
## anterior. Cuántas brasas, cuánto duran y su color viven en el nodo.


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		restart()
