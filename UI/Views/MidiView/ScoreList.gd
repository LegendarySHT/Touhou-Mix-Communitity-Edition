extends BaseScrollList

class_name ScoreList

func _ready() -> void:
	var node = create_and_add_item("1", "score")
	node.setup_score(1, 99999, "SS", 99.99, 19.01, 1000, 100, 1, 0, 0)
