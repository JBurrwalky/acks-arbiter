class_name VassalAppointmentWarnings
extends RefCounted

## Phase 11D.4 — per gdd-domain-style-and-alignment.md §9.6 (Q-DSA-4 resolution).
##
## Returns human-readable warning strings for the player-confirmation modal
## that fires when assigning a domain to a henchman vassal-ruler. The
## warnings surface the stacked morale penalties that the appointment will
## incur (alignment mismatch, beastman-rules-kin stack) so the player can
## make an informed choice. The Confirm button is NOT disabled by these —
## they are informational; the player may proceed knowing the cost.
##
## The same helper is reused by the establishment-flow modal when the player
## conquers a chaotic-kin civilized domain, where the −2 alignment penalty
## alone is worth warning about; the helper's single-warning case handles it.
##
## NPC-side appointments don't consult this helper — the AI ledger absorbs
## the stacked penalty automatically; no warning is needed because no player
## choice is being made.

# Beastman race set per memory/feedback_acks_kin_terminology.md +
# DomainMoraleResolver.BEASTMAN_RACES. Kept in sync via the linked constant
# (the resolver's set is canonical; this list mirrors for cheap lookup).
const _BEASTMAN_RACES := [
	"hobgoblin", "orc", "gnoll", "goblin", "bugbear", "kobold", "ogre", "troll",
]


## Returns Array[String] of warning strings keyed to the relevant penalties.
## Empty array means no warnings — appointment is benign. Caller renders
## each string as a bullet above the Confirm button.
##
## [param henchman_character_id] — the prospective new vassal ruler.
## [param target_domain_id]      — the domain being appointed to them.
static func warnings_for_appointment(
	henchman_character_id: String,
	target_domain_id: String
) -> Array:
	var warnings: Array = []
	if henchman_character_id.is_empty() or target_domain_id.is_empty():
		return warnings
	var henchman: Dictionary = CampaignRepository.get_character(henchman_character_id)
	var domain: Dictionary = CampaignRepository.get_domain(target_domain_id)
	if henchman.is_empty() or domain.is_empty():
		return warnings
	var h_align: String = String(henchman.get("alignment", "neutral")).to_lower()
	var d_align: String = String(domain.get("alignment", "neutral")).to_lower()
	var h_race: String = String(henchman.get("race", "")).to_lower()
	var establishment_method: String = String(domain.get("establishment_method", "")).to_lower()
	var domain_is_beastman: bool = establishment_method in ["clanhold_annex", "recruit_chieftain"]
	var henchman_is_beastman: bool = _BEASTMAN_RACES.has(h_race)

	# Alignment-vs-religion penalty per acore_axioms L466-471.
	if h_align != d_align:
		var lc_pair := (h_align == "lawful" and d_align == "chaotic") \
			or (h_align == "chaotic" and d_align == "lawful")
		if lc_pair:
			warnings.append(
				"−2 base morale: %s ruler in %s domain (per acore_axioms §alignment_and_religion)."
				% [h_align.capitalize(), d_align.capitalize()])
		else:
			warnings.append(
				"−1 base morale: %s ruler in %s domain (per acore_axioms §alignment_and_religion)."
				% [h_align.capitalize(), d_align.capitalize()])

	# Beastman-rules-kin stack per ax_domains_of_chaos.xml:44.
	if henchman_is_beastman and not domain_is_beastman:
		warnings.append(
			"−2 base morale: beastman ruler over kin domain "
			+ "(per ax_domains_of_chaos §realm_management — stacks ON TOP of alignment penalty).")

	# Phase 11D.4 hook: religion-conversion mention when a stacked −3 or
	# worse would apply. Player can mitigate via a religion-conversion arc
	# per gdd-religion-conversion.md.
	if warnings.size() >= 2:
		warnings.append(
			"These penalties apply until religion conversion completes. "
			+ "The new ruler may initiate Change Religion from the Decrees sub-tab "
			+ "(or via their Faith block if they are a divine caster).")

	return warnings
