extends VBoxContainer

## Class-Specific sub-tab — Domain Phase 10A.1 dispatcher.
##
## Reads the active domain's owner_character_id, queries ClassBucketResolver
## for the applicable buckets, then instantiates one collapsible card per
## bucket. The cards themselves are placeholders in 10A.1; concrete content
## ships in:
##   - 10A.2: Faith block
##   - 10A.3: Garrison Training block (+ Bardic Patronage variant)
##   - 10B.1: Magical Research block
##   - 10B.2: Trade block
##   - 10B.3: Syndicate block
##
## Per gdd-domain-tab.md §12.8 the blocks render as collapsible cards. The
## primary bucket (per ClassBucketResolver.PRIMARY_BUCKET_OVERRIDE or first
## in canonical order) is expanded by default; others collapsed. Per-entity-
## per-bucket collapse state persists in NotebookState substate under
## `class_specific.collapse_state[entity_id][bucket_id]`.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FaithBlockScript := preload("res://scenes/ui/notebook/domain/blocks/faith_block.gd")
const BardicPatronageBlockScript := preload("res://scenes/ui/notebook/domain/blocks/bardic_patronage_block.gd")
const MagicalResearchBlockScript := preload("res://scenes/ui/notebook/domain/blocks/magical_research_block.gd")

const _PLACEHOLDER_LABELS := {
	"trade":              "Trade block — guildhouse, monopoly, mercantile ventures.",
	"syndicate":          "Syndicate block — hijinks, hideout management, crime & punishment.",
}

const _PLACEHOLDER_PHASES := {
	"trade":              "Phase 10B.2",
	"syndicate":          "Phase 10B.3",
}


# ---------------------------------------------------------------------------
# Fields
# ---------------------------------------------------------------------------

var _domain_data: Dictionary = {}
var _owner_character_id: String = ""

## bucket_id → CollapsibleContainer (or PanelContainer wrapper) holding the
## block's body.
var _block_cards: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)


# ---------------------------------------------------------------------------
# Public API (called by domain_tab_page._render_active_content)
# ---------------------------------------------------------------------------

func display(domain_data: Dictionary) -> void:
	_domain_data = domain_data
	_owner_character_id = String(domain_data.get("owner_character_id", ""))
	_rebuild()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _rebuild() -> void:
	# Clear prior content and re-render. Block cards are recreated each rebuild
	# so the bucket list responds to in-session class/level changes (e.g. a
	# fighter advancing from L4 to L5 unlocks garrison_training).
	for child in get_children():
		child.queue_free()
	_block_cards.clear()

	if _owner_character_id.is_empty():
		_add_dim_label("This sub-tab requires an active entity that owns the domain.")
		return

	var buckets: Array[String] = ClassBucketResolver.buckets_for(_owner_character_id)
	if buckets.is_empty():
		# This shouldn't happen in normal flow because the parent tab page
		# hides the strip entry for empty-bucket entities. Render a defensive
		# message in case it does.
		_add_dim_label(
			"This entity's class has no class-specific high-level activities surfaced "
			+ "by the Domain tab. (See gdd-domain-tab.md §12.1 matrix for which classes "
			+ "see this sub-tab.)"
		)
		return

	var primary: String = ClassBucketResolver.primary_bucket_for(_owner_character_id)
	for bucket_id in buckets:
		var card := _make_block_card(bucket_id, bucket_id == primary)
		add_child(card)
		_block_cards[bucket_id] = card


func _make_block_card(
	bucket_id: String,
	expanded_by_default: bool,
) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Header row with toggle button + label.
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.text = "▼" if expanded_by_default else "▶"
	toggle.button_pressed = expanded_by_default
	toggle.flat = true
	toggle.custom_minimum_size = Vector2(28, 0)
	header.add_child(toggle)
	var title := Label.new()
	title.text = String(ClassBucketResolver.BUCKET_LABELS.get(bucket_id, bucket_id))
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	vbox.add_child(header)

	# Body container — visible when expanded.
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	body.visible = expanded_by_default
	vbox.add_child(body)

	# Bucket-specific content. Phases ship blocks per the wave-split plan.
	# Faith block ships in Phase 10A.2; other buckets remain placeholders for
	# their target phase.
	if bucket_id == "faith":
		var faith_block: VBoxContainer = FaithBlockScript.new()
		faith_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(faith_block)
		var domain_id: String = String(_domain_data.get("id", ""))
		faith_block.bind(_owner_character_id, domain_id, _resolve_party_id())
	elif bucket_id == "bardic_patronage":
		var bardic_block: VBoxContainer = BardicPatronageBlockScript.new()
		bardic_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(bardic_block)
		var domain_id: String = String(_domain_data.get("id", ""))
		bardic_block.bind(_owner_character_id, domain_id, _resolve_party_id())
	elif bucket_id == "magical_research":
		var mr_block: VBoxContainer = MagicalResearchBlockScript.new()
		mr_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(mr_block)
		var domain_id: String = String(_domain_data.get("id", ""))
		mr_block.bind(_owner_character_id, domain_id, _resolve_party_id())
	else:
		var label_text: String = _PLACEHOLDER_LABELS.get(bucket_id, "")
		var phase_text: String = _PLACEHOLDER_PHASES.get(bucket_id, "a future phase")
		var description := Label.new()
		description.text = "%s\n\nFull content lands in %s." % [label_text, phase_text]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(description)

	# Wire toggle.
	toggle.toggled.connect(func(pressed: bool) -> void:
		toggle.text = "▼" if pressed else "▶"
		body.visible = pressed
	)
	return panel


func _resolve_party_id() -> String:
	var pid: String = GameState.active_party_id
	if pid.is_empty():
		pid = GameState.party_id
	return pid


func _add_dim_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1, 1, 1, 0.6)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(label)
