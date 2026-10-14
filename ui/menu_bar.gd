extends HBoxContainer
signal action_requested(action: String)

const FILE_ACTIONS := {0: "New", 1: "Open", 16:"OpenRecent", 3: "Save", 4: "SaveAs", 5: "Recover", 7: "Import", 8: "Pattern", 9: "Stamp", 11: "Export", 12: "ExportModel", 14: "Quit", 15:"ExportMaps", 17:"ToggleRestoreLast"}
const EDIT_ACTIONS := {0: "Undo", 1: "Redo", 3: "ClearSelection", 4: "GrowSelection", 5: "ShrinkSelection", 7: "ResetMap", 9:"ResizeTexture", 10:"ReplaceColor"}
const VIEW_ACTIONS := {0: "Frame", 1: "FitUV", 2: "WireUV", 3: "ToggleUV", 4: "WireModel", 6: "ToggleFullscreen"}

func _ready() -> void:
	$File.get_popup().id_pressed.connect(func(id: int):
		if FILE_ACTIONS.has(id): action_requested.emit(FILE_ACTIONS[id]))
	$Edit.get_popup().id_pressed.connect(func(id: int):
		if EDIT_ACTIONS.has(id): action_requested.emit(EDIT_ACTIONS[id]))
	$View.get_popup().id_pressed.connect(func(id: int):
		if VIEW_ACTIONS.has(id): action_requested.emit(VIEW_ACTIONS[id]))
	$Help.get_popup().id_pressed.connect(func(id: int):
		if id == 0: action_requested.emit("About"))

func refresh(can_undo: bool, can_redo: bool, can_recover: bool, recent_path := "", restore_last := true, channel := "Albedo") -> void:
	$Edit.get_popup().set_item_disabled(0, not can_undo)
	$Edit.get_popup().set_item_disabled(1, not can_redo)
	$File.get_popup().set_item_disabled(2, recent_path.is_empty())
	$File.get_popup().set_item_text(2, "Open last project…   " + recent_path.get_file() if not recent_path.is_empty() else "Open last project…")
	$File.get_popup().set_item_disabled(6, not can_recover)
	$File.get_popup().set_item_checked(16, restore_last)
	$File.get_popup().set_item_text(12, "Export " + channel + " PNG…   ·   Ctrl+E")
