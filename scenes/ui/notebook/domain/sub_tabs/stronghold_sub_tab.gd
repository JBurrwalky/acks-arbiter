extends VBoxContainer

## Stronghold sub-tab — Phase 2 lands a placeholder body that lists owned
## strongholds (if any) and exposes the cross-activation buttons for Phase 1's
## CommissionWizard and ClaimStrongholdModal. The full sub-tab spec
## (sufficiency gauge / pending construction list / non-conforming badges)
## is finished in Phase 4 per `docs/domain-roadmap-corrected.md`.


var _domain_id: String = ""
var _domain_data: Dictionary = {}

var _list_container: VBoxContainer = null
var _commission_btn: Button = null
var _claim_btn: Button = null


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	_build_ui()


func _build_ui() -> void:
	var heading := Label.new()
	heading.text = "Strongholds"
	heading.add_theme_font_size_override("font_size", 18)
	add_child(heading)
	_list_container = VBoxContainer.new()
	_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_list_container)
	var btn_row := HBoxContainer.new()
	add_child(btn_row)
	_commission_btn = Button.new()
	_commission_btn.text = "Commission new structure…"
	_commission_btn.pressed.connect(_on_commission_pressed)
	btn_row.add_child(_commission_btn)
	_claim_btn = Button.new()
	_claim_btn.text = "Claim existing structure…"
	_claim_btn.pressed.connect(_on_claim_pressed)
	btn_row.add_child(_claim_btn)
	var note := Label.new()
	note.text = (
		"Phase 4 expands this sub-tab with sufficiency gauge, in-progress "
		+ "construction list, and divine-favor / non-conforming badges. "
		+ "Phase 2 ships only the cross-activation buttons."
	)
	note.modulate = Color(0.7, 0.7, 0.7)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_domain_id = String(domain_data.get("id", ""))
	_render_list()


func _render_list() -> void:
	for child in _list_container.get_children():
		_list_container.remove_child(child)
		child.queue_free()
	if _domain_id.is_empty():
		var empty := Label.new()
		empty.text = "—"
		_list_container.add_child(empty)
		return
	var strongholds := CampaignRepository.list_domain_strongholds(_domain_id)
	if strongholds.is_empty():
		var empty := Label.new()
		empty.text = (
			"No strongholds in this domain. Without sufficient stronghold "
			+ "value your peasants generate no income and your domain does "
			+ "not grow."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_container.add_child(empty)
		return
	for s in strongholds:
		var lbl := Label.new()
		lbl.text = "%s (%s)  —  %d gp value  —  %d%% complete  —  %s" % [
			String(s.get("structure_type", "?")),
			String(s.get("archetype", "?")),
			int(s.get("gp_value", 0)),
			int(s.get("completion_pct", 0)),
			String(s.get("status", "?")),
		]
		_list_container.add_child(lbl)


func _on_commission_pressed() -> void:
	# Phase 4 wires this to instantiate the Phase 1 commission_wizard.tscn
	# inline. Phase 2 emits a notification so the player knows the surface is
	# pending.
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "system",
		"title": "Commission Wizard",
		"body": (
			"The full commission flow lands when the Stronghold sub-tab is "
			+ "completed in Phase 4. Phase 2 wires the button; Phase 4 hosts "
			+ "the wizard inline."
		),
	})


func _on_claim_pressed() -> void:
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "system",
		"title": "Claim Modal",
		"body": (
			"The full claim flow lands when the Stronghold sub-tab is "
			+ "completed in Phase 4. Phase 2 wires the button; Phase 4 hosts "
			+ "the modal inline."
		),
	})
