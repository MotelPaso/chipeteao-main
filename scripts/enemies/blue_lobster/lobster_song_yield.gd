class_name LobsterSongYield
extends Node
## El final de la canción de la Langosta Azul (nodo Yield, hijo del nodo Music
## de LobsterEntrance.tscn). Si arranca la canción de OTRO jefe mientras esta
## suena (Mythos llega cuando la langosta acaba de morir y su canción todavía
## se apaga), esta le deja el lugar: se apaga rápido (BossSong.hand_over).
## Procesa SIEMPRE: la cinemática del otro jefe congela el mundo y pausa lo
## demás.

## True desde que esta canción le dejó el lugar a otra.
var _yielded: bool = false

@onready var _song: BossSong = get_parent() as BossSong


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _song == null:
		return
	if not _song.is_live():
		_yielded = false
		return
	if _yielded:
		return
	for node: Node in get_tree().get_nodes_in_group(BossSong.GROUP):
		var other := node as BossSong
		if other != null and other != _song and other.is_live():
			_yielded = true
			_song.hand_over()
			return
