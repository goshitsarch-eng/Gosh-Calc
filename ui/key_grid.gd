class_name GcKeyGrid
extends Container
## Equal-cell grid with column spans (GridContainer has none). Children carry an
## optional integer meta "span". Rows share the available height equally.

var columns := 4
var gap := 7
var min_row_height := 44
## 0 means as many rows as the children need.
var fixed_rows := 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		update_minimum_size()
	elif what == NOTIFICATION_SORT_CHILDREN:
		_layout()


func set_metrics(new_columns: int, new_gap: int, new_fixed_rows: int = 0) -> void:
	columns = new_columns
	gap = new_gap
	fixed_rows = new_fixed_rows
	update_minimum_size()
	queue_sort()


func _placements() -> Array:
	# [[child, col, row, span], ...] in child order, wrapping at `columns`
	var out := []
	var col := 0
	var row := 0
	for child in get_children():
		if not child is Control or not child.visible:
			continue
		var span: int = mini(child.get_meta("span", 1), columns)
		if col + span > columns:
			col = 0
			row += 1
		out.append([child, col, row, span])
		col += span
		if col >= columns:
			col = 0
			row += 1
	return out


func _row_count(placements: Array) -> int:
	if fixed_rows > 0:
		return fixed_rows
	var rows := 0
	for p in placements:
		rows = maxi(rows, p[2] + 1)
	return rows


func _get_minimum_size() -> Vector2:
	var rows := _row_count(_placements())
	return Vector2(columns * 30, rows * min_row_height + maxi(rows - 1, 0) * gap)


func _layout() -> void:
	var placements := _placements()
	var rows := _row_count(placements)
	if rows == 0:
		return
	var cell_w := (size.x - (columns - 1) * gap) / columns
	var cell_h := (size.y - (rows - 1) * gap) / rows
	for p in placements:
		var rect := Rect2(
				p[1] * (cell_w + gap), p[2] * (cell_h + gap),
				cell_w * p[3] + gap * (p[3] - 1), cell_h)
		fit_child_in_rect(p[0], rect)
