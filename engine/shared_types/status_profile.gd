class_name StatusProfile
extends RefCounted

## Social Status Profile (gdd-npc-dialogue.md §7). An EVIDENCE ASSEMBLER, not a
## new modifier: ACKS has no aggregate "status score" that touches dice (§7.1).
## This struct carries (a) the RAW-modifier-line evidence InteractionResolver
## already consumes (dice-affecting, sacred mapping) and (b) a project-designed
## status_tier that drives ONLY narration + the §6.5 per-issue status-differential
## modifier — it NEVER feeds the sacred tone-track tables.
##
## Computed at session open and on speaker change by StatusProfileBuilder.build();
## NOT persisted — all inputs (reputation, titles, worn equipment, party roster,
## NPC memories) already persist. No DB table (§7.3).

# --- status tier vocabulary (five tiers, low -> high), §7.2 ---
const TIER_OUTCAST := "outcast"
const TIER_COMMON := "common"
const TIER_RESPECTABLE := "respectable"
const TIER_NOTABLE := "notable"
const TIER_EXALTED := "exalted"
const TIERS: Array = [TIER_OUTCAST, TIER_COMMON, TIER_RESPECTABLE, TIER_NOTABLE, TIER_EXALTED]

# --- harm evidence tiers (§7.2): 0 none / 1 believed / 2 witnessed / 3 personally harmed ---
const HARM_NONE := 0
const HARM_BELIEVED := 1
const HARM_WITNESSED := 2
const HARM_PERSONAL := 3

# === evidence consumed by RAW modifier lines (dice-affecting, sacred mapping) ===
var believed_alignment: String = "neutral"   # from reputation + public deeds, NOT true alignment
var noble_ranks: int = 0                      # titles held (realms/titles), for ax_reactions:254
var legal_authority_over_target: bool = false # domain office vs. target's residence/fealty
var favors_owed_to_party: int = 0
var favors_owed_by_party: int = 0
var entourage_count: int = 0                  # present PCs + henchmen + troops -> outnumber ratios
var speaker_level: int = 1
var brandishing_weapon: bool = false
var brandishing_magic: bool = false
var harm_evidence_tier: int = 0               # 0 none / 1 believed / 2 witnessed / 3 personally harmed

# === status tier (narration + per-issue differential §6.5; never sacred tone tables) ===
var status_tier: String = TIER_COMMON
var dress_quality: String = "common"          # from worn-equipment value bands
var fame_notes: Array = []                    # top reputation reasons


## Numeric rank of the status_tier (0 outcast .. 4 exalted), for §6.5 differential.
func tier_rank() -> int:
	var idx := TIERS.find(status_tier)
	return idx if idx >= 0 else 1


## The §6.5 status-differential modifier for a Track-2 per-issue roll, given the
## NPC's own status tier and whether the ask is RELEVANT to that NPC's quests /
## faction goals (§6.5). Party-outranks: +1 (+2 at differential >= 3). NPC-outranks:
## -1 per tier, but ONLY for requests NOT related to the NPC's interests.
## Constants PROJECT CALL, tunable. Never applied to Track-1 tone rolls.
func status_differential_modifier(npc_tier_rank: int, ask_is_relevant: bool) -> int:
	var party_rank := tier_rank()
	var diff := party_rank - npc_tier_rank
	if diff > 0:
		# Party outranks: +1, +2 at differential >= 3 (deliberately smaller, §6.5).
		return 2 if diff >= 3 else 1
	if diff < 0:
		# NPC outranks: -1 per tier of differential, waived for related asks.
		if ask_is_relevant:
			return 0
		return diff   # negative (e.g. -2 at two tiers below)
	return 0


## Assemble the InteractionResolver-context keys this evidence feeds (§7.2).
## The caller merges these into the resolver context for a dice-affecting move.
## Only the RAW-line evidence is emitted here — status_tier is intentionally
## excluded (it never touches the sacred tables, §7.1).
func to_resolver_context() -> Dictionary:
	var ctx := {
		"speaker_level": speaker_level,
		"brandishing_weapon": brandishing_weapon,
		"character_brandishing_magic": brandishing_magic,
	}
	if noble_ranks > 0:
		# RAW seduction status line: +1 per noble rank (ax_reactions:253-254).
		# Tone-scoped in InteractionResolver._apply_seduction — the diplomatic
		# and intimidation stacks have NO noble-rank line (verified RAW), so this
		# key is inert for those tones even though it rides in the shared context.
		ctx["noble_ranks"] = noble_ranks
	if legal_authority_over_target:
		ctx["has_legal_authority"] = true
	if favors_owed_by_party > 0:
		ctx["favors_owed_to_target"] = favors_owed_by_party
	if favors_owed_to_party > 0:
		ctx["favors_owed_to_character"] = favors_owed_to_party
	# Harm evidence maps to the three RAW threat lines (ax_reactions:101-105):
	# believed -> harmed_friends_belief (-2); witnessed -> harmed_friends_witnessed
	# (-5); personally harmed -> personally_harmed (-5). Highest tier wins (they are
	# not additive in RAW — a personally-harmed target is not ALSO "believed").
	match harm_evidence_tier:
		HARM_BELIEVED:
			ctx["harmed_friends_belief"] = true
		HARM_WITNESSED:
			ctx["harmed_friends_witnessed"] = true
		HARM_PERSONAL:
			ctx["personally_harmed"] = true
	return ctx


func to_dict() -> Dictionary:
	return {
		"believed_alignment": believed_alignment,
		"noble_ranks": noble_ranks,
		"legal_authority_over_target": legal_authority_over_target,
		"favors_owed_to_party": favors_owed_to_party,
		"favors_owed_by_party": favors_owed_by_party,
		"entourage_count": entourage_count,
		"speaker_level": speaker_level,
		"brandishing_weapon": brandishing_weapon,
		"brandishing_magic": brandishing_magic,
		"harm_evidence_tier": harm_evidence_tier,
		"status_tier": status_tier,
		"dress_quality": dress_quality,
		"fame_notes": fame_notes.duplicate(),
	}


static func from_dict(data: Dictionary) -> StatusProfile:
	var s := StatusProfile.new()
	s.believed_alignment = data.get("believed_alignment", "neutral")
	s.noble_ranks = int(data.get("noble_ranks", 0))
	s.legal_authority_over_target = bool(data.get("legal_authority_over_target", false))
	s.favors_owed_to_party = int(data.get("favors_owed_to_party", 0))
	s.favors_owed_by_party = int(data.get("favors_owed_by_party", 0))
	s.entourage_count = int(data.get("entourage_count", 0))
	s.speaker_level = int(data.get("speaker_level", 1))
	s.brandishing_weapon = bool(data.get("brandishing_weapon", false))
	s.brandishing_magic = bool(data.get("brandishing_magic", false))
	s.harm_evidence_tier = int(data.get("harm_evidence_tier", 0))
	s.status_tier = data.get("status_tier", TIER_COMMON)
	s.dress_quality = data.get("dress_quality", "common")
	var notes = data.get("fame_notes", [])
	s.fame_notes = (notes as Array).duplicate() if notes is Array else []
	return s
