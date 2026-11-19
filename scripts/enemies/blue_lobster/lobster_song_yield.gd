class_name LobsterSongYield
extends Node
## El final de la canción de la Langosta Azul (nodo Yield, hijo del nodo Music
## de LobsterEntrance.tscn). Dos cosas que nadie más puede hacer, porque la
## cinemática de otro jefe congela la arena y con ella a la entrada de la
## langosta; por eso este nodo procesa SIEMPRE:
##   - Si arranca la canción de OTRO jefe mientras esta suena (Mythos llega
##     cuando la langosta acaba de morir y su canción todavía se apaga), esta
##     le deja el lugar: se apaga rápido (BossSong.hand_over).
##   - Cuando la langosta ya no está y la canción terminó de apagarse, la
##     entrada sobra: se libera sola (así no queda una segunda cinemática de
##     jefe colgada de la arena).

## La entrada a la que pertenece (la raíz de su escena).
var _entrance: LobsterEntrance = null
## True desde que esta canción le dejó el lugar a otra.
var _yielded: bool = false

@onready var _song: BossSong = get_parent() as BossSong


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_entrance = owner as LobsterEntrance


func _process(_delta: float) -> void:
	if _song == null or _entrance == null:
		return
	if not _song.is_live():
		_yielded = false
		if _entrance.is_spent():
			_entrance.queue_free()
		return
	if _yielded:
		return
	for node: Node in get_tree().get_nodes_in_group(BossSong.GROUP):
		var other := node as BossSong
		if other != null and other != _song and other.is_live():
			_yielded = true
			_song.hand_over()
			return
