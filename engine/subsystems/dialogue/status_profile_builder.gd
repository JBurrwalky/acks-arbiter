class_name StatusProfileBuilder
extends RefCounted

## Assembles a StatusProfile (gdd-npc-dialogue.md §7) at session open and on
## speaker change. NOT an aggregate "status score" — an EVIDENCE assembler that
## gathers what RAW's modifier lines already require about the party, plus a
## project-designed status_tier for narration + the §6.5 per-issue differential.
##
## Computed-not-persisted (§7.3): every input already persists (reputation rows,
## realms/titles, worn inventory, party roster, this NPC's memories). No new table.
##
## believed_alignment / harm_evidence_tier derive from ReputationSystem.
## get_effective_score() per scope PLUS this NPC's OWN memories — a personally-
## witnessed crime uses the -5 (harm tier 2/3), not the hearsay -2 (harm tier 1)
## (ax_reactions:101-105). status_tier is reputation tier + noble rank + dress
## band + entourage. Deterministic; no RNG.

# --- dress-quality value bands (worn-equipment total value in cp), PROJECT CALL ---
const DRESS_MEAN_MAX_CP := 5000        # < 50 gp of worn gear -> "mean"
const DRESS_COMMON_MAX_CP := 50000     # < 500 gp -> "common"
const DRESS_FINE_MAX_CP := 500000      # < 5000 gp -> "fine"
# >= 5000 gp -> "sumptuous"
const DRESS_DEFAULT_ITEM_CP := 100     # value fallback for a worn item with value_cp = -1

# worn (non-pack) equipment slots that read as "dress" for the appearance line.
const _WORN_SLOTS: Array = [
	"head", "neck", "arms", "armor", "torso_clothing", "legs_clothing",
	"belt", "feet", "hands_worn", "cloak", "ring_l", "ring_r", "hands_main",
]

# reputation-score thresholds mapping a personal/settlement effective score to a
# status contribution. Positive fame lifts the tier; deep infamy sinks it.
const FAME_NOTABLE_SCORE := 40
const FAME_EXALTED_SCORE := 70
const INFAMY_OUTCAST_SCORE := -40


## Build the StatusProfile for a (party, speaker, npc) triple. [param scene]
## carries scene flags (settlement_id / domain_id for reputation scope,
## brandishing flags). [param rep_system] is an optional ReputationSystem; when
## null the builder constructs one from CampaignRepository + the active party so
## reputation evidence still lands. Returns a StatusProfile (never null).
static func build(party_id: String, speaker_id: String, npc_id: String,
		scene: Dictionary = {}, rep_system = null) -> StatusProfile:
	var profile := StatusProfile.new()
	var campaign_id: String = String(scene.get("campaign_id", GameState.campaign_id))
	var rep = rep_system
	if rep == null:
		rep = ReputationSystem.new(CampaignRepository, campaign_id, party_id)

	# --- speaker-derived evidence ---
	var speaker: Dictionary = _character(speaker_id)
	profile.speaker_level = int(speaker.get("level", 1))
	profile.brandishing_weapon = bool(scene.get("brandishing_weapon", false))
	profile.brandishing_magic = bool(scene.get("brandishing_magic", false))

	# --- believed alignment + harm evidence (reputation + this NPC's memories) ---
	profile.believed_alignment = _believed_alignment(rep, npc_id, scene)
	profile.harm_evidence_tier = _harm_evidence_tier(rep, campaign_id, npc_id, party_id, scene)

	# --- noble rank + legal authority ---
	profile.noble_ranks = _noble_ranks(campaign_id, speaker_id)
	profile.legal_authority_over_target = _has_legal_authority(campaign_id, speaker_id, npc_id, scene)

	# --- favor ledger (from the relationship row) ---
	var rel: Dictionary = CampaignRepository.get_npc_relationship(campaign_id, npc_id, party_id)
	profile.favors_owed_to_party = int(rel.get("favors_owed_to_party", 0))
	profile.favors_owed_by_party = int(rel.get("favors_owed_by_party", 0))

	# --- entourage (present PCs + henchmen + troops) ---
	profile.entourage_count = _entourage_count(party_id, scene)

	# --- dress quality ---
	profile.dress_quality = _dress_quality(speaker_id)

	# --- fame notes + status tier ---
	var fame_score := _fame_score(rep, npc_id, scene)
	profile.fame_notes = _fame_notes(rep, npc_id, scene)
	profile.status_tier = _status_tier(profile, fame_score)
	return profile


# ---------------------------------------------------------------------------
# Believed alignment + harm evidence
# ---------------------------------------------------------------------------

## Believed alignment (§7.2): the reputation-derived public perception. Deeply
## infamous parties read as chaotic regardless of true alignment; otherwise the
## speaker's declared alignment is the public read (Phase 2 keeps this simple —
## full public-deeds inference is a later pass).
static func _believed_alignment(rep, npc_id: String, scene: Dictionary) -> String:
	var eff := _effective_score(rep, npc_id, scene)
	if eff <= INFAMY_OUTCAST_SCORE:
		return "chaotic"
	return "neutral"


## Harm evidence tier (§7.2). Reputation supplies the hearsay floor (believed);
## THIS NPC's own memories escalate it: a `grudge`/`deception_suffered` memory
## about the party, or a witnessed/personal-harm fact, uses the -5 lines
## (ax_reactions:103-105) rather than the hearsay -2. Highest tier wins.
static func _harm_evidence_tier(rep, campaign_id: String, npc_id: String,
		party_id: String, scene: Dictionary) -> int:
	var tier := StatusProfile.HARM_NONE
	# Reputation floor: a hostile personal/settlement score is "believed harm".
	var eff := _effective_score(rep, npc_id, scene)
	if eff <= INFAMY_OUTCAST_SCORE:
		tier = StatusProfile.HARM_BELIEVED
	# This NPC's OWN memories can escalate (personally witnessed / suffered).
	var mems: Array = CampaignRepository.list_npc_memories(campaign_id, npc_id, 24)
	for m in mems:
		# Only memories about THIS party count as personal witness.
		if String(m.get("party_id", "")) != party_id and String(m.get("party_id", "")) != "":
			continue
		var kind := String(m.get("kind", ""))
		if kind == "grudge":
			# A grudge the NPC personally holds -> witnessed-tier harm.
			tier = maxi(tier, StatusProfile.HARM_WITNESSED)
		var facts = m.get("facts", [])
		if facts is String:
			facts = JSON.parse_string(facts)
		if facts is Array:
			for f in facts:
				if f is Dictionary:
					if f.has("personally_harmed") and bool(f["personally_harmed"]):
						tier = maxi(tier, StatusProfile.HARM_PERSONAL)
					elif f.has("witnessed_harm") and bool(f["witnessed_harm"]):
						tier = maxi(tier, StatusProfile.HARM_WITNESSED)
	return tier


# ---------------------------------------------------------------------------
# Noble rank + legal authority
# ---------------------------------------------------------------------------

## Noble ranks (§7.2, ax_reactions:254): count of realms this character heads
## PLUS a non-empty `characters.title` field. Deterministic DB reads.
static func _noble_ranks(campaign_id: String, character_id: String) -> int:
	if character_id.is_empty():
		return 0
	var ranks := 0
	var c: Dictionary = _character(character_id)
	if String(c.get("title", "")).strip_edges() != "":
		ranks += 1
	# Realms headed by this character (a seated title).
	if CampaignRepository.db != null:
		CampaignRepository.db.query_with_bindings(
			"SELECT COUNT(*) AS cnt FROM realms WHERE campaign_id = ? AND head_character_id = ?",
			[campaign_id, character_id])
		if not CampaignRepository.db.query_result.is_empty():
			ranks += int(CampaignRepository.db.query_result[0].get("cnt", 0))
	return ranks


## Legal authority over the target (§7.2): the speaker holds a domain office and
## the target resides in / owes fealty within that domain. Phase 2 reads an
## explicit scene flag (`speaker_has_authority_over_npc`) so the entry-point layer
## can supply the domain-office resolution it already owns; defaults false.
static func _has_legal_authority(_campaign_id: String, _speaker_id: String,
		_npc_id: String, scene: Dictionary) -> bool:
	return bool(scene.get("speaker_has_authority_over_npc", false))


# ---------------------------------------------------------------------------
# Entourage + dress
# ---------------------------------------------------------------------------

static func _entourage_count(party_id: String, scene: Dictionary) -> int:
	var count := 0
	if party_id != "":
		var members: Array = CampaignRepository.get_party_members(party_id)
		count = members.size()
	# Scene may add attached troops (army context) on top of the roster.
	count += int(scene.get("attached_troop_count", 0))
	return count


## Dress quality band from the total value of the speaker's WORN (equipped,
## non-pack) equipment. value_cp = -1 falls back to a nominal per-item value so
## sparse test fixtures still band as "common" rather than "mean".
static func _dress_quality(speaker_id: String) -> String:
	if speaker_id.is_empty():
		return "common"
	var total_cp := 0
	var items: Array = CampaignRepository.get_inventory_items(speaker_id)
	for it in items:
		if not (it is Dictionary):
			continue
		if int(it.get("is_equipped", 0)) != 1:
			continue
		var slot := String(it.get("slot", "pack"))
		if not _WORN_SLOTS.has(slot):
			continue
		var v := int(it.get("value_cp", -1))
		if v < 0:
			v = DRESS_DEFAULT_ITEM_CP
		total_cp += v
	if total_cp < DRESS_MEAN_MAX_CP:
		return "mean"
	if total_cp < DRESS_COMMON_MAX_CP:
		return "common"
	if total_cp < DRESS_FINE_MAX_CP:
		return "fine"
	return "sumptuous"


# ---------------------------------------------------------------------------
# Fame + status tier
# ---------------------------------------------------------------------------

static func _status_tier(profile: StatusProfile, fame_score: int) -> String:
	# Base tier from fame/infamy score.
	var rank := 1   # common
	if fame_score <= INFAMY_OUTCAST_SCORE:
		rank = 0     # outcast
	elif fame_score >= FAME_EXALTED_SCORE:
		rank = 4     # exalted
	elif fame_score >= FAME_NOTABLE_SCORE:
		rank = 3     # notable
	# Noble rank lifts the tier (a titled lord is at least "notable").
	if profile.noble_ranks >= 1:
		rank = maxi(rank, 3)
	if profile.noble_ranks >= 2:
		rank = maxi(rank, 4)
	# Dress + entourage nudge upward when not already infamous.
	if rank > 0:
		if profile.dress_quality == "sumptuous":
			rank = maxi(rank, 3)
		elif profile.dress_quality == "fine":
			rank = maxi(rank, 2)
		if profile.entourage_count >= 20:
			rank = maxi(rank, 3)
	rank = clampi(rank, 0, 4)
	return StatusProfile.TIERS[rank]


static func _fame_score(rep, npc_id: String, scene: Dictionary) -> int:
	return _effective_score(rep, npc_id, scene)


static func _fame_notes(rep, npc_id: String, scene: Dictionary) -> Array:
	# Top reputation reasons (§7.2). Phase 2 surfaces the personal-rep last_reason
	# where one exists; richer deed-fame is a later pass.
	var notes: Array = []
	if rep == null:
		return notes
	var entry = rep.get_reputation(ReputationEntry.SCOPE_TIER_A_NPC, npc_id) \
		if npc_id != "" else null
	if entry != null and String(entry.last_reason).strip_edges() != "":
		notes.append(entry.last_reason)
	var settlement_id := String(scene.get("settlement_id", ""))
	if settlement_id != "":
		var s_entry = rep.get_reputation(ReputationEntry.SCOPE_SETTLEMENT, settlement_id)
		if s_entry != null and String(s_entry.last_reason).strip_edges() != "":
			notes.append(s_entry.last_reason)
	return notes


## The most-specific effective reputation score for this encounter: personal NPC
## reputation if any, else the settlement/domain cascade from the scene.
static func _effective_score(rep, npc_id: String, scene: Dictionary) -> int:
	if rep == null:
		return 0
	var best := 0
	if npc_id != "":
		var personal := rep.get_score(ReputationEntry.SCOPE_TIER_A_NPC, npc_id)
		if personal == 0:
			personal = rep.get_score(ReputationEntry.SCOPE_TIER_B_NPC, npc_id)
		best = personal
	var settlement_id := String(scene.get("settlement_id", ""))
	if settlement_id != "":
		var s := rep.get_effective_score(ReputationEntry.SCOPE_SETTLEMENT, settlement_id)
		if abs(s) > abs(best):
			best = s
	var domain_id := String(scene.get("domain_id", ""))
	if domain_id != "" and settlement_id == "":
		var d := rep.get_effective_score(ReputationEntry.SCOPE_DOMAIN, domain_id)
		if abs(d) > abs(best):
			best = d
	return best


static func _character(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	return CampaignRepository.get_character(character_id)
