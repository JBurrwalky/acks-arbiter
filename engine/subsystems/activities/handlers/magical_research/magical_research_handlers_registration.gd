class_name MagicalResearchActivityHandlersRegistration
extends RefCounted

## Registers magical_research-category activity handlers with an
## ActivityHandlerRegistry. Phase 10B.1a ships the registration shell with
## no concrete handlers wired; subsequent waves attach handlers as they land:
##
##   10B.1b — research_magic (spell targets only) + rewrite_spell +
##            replace_spell + scribe_spell
##   10B.1c — research_magic (magic_item target) + manage_assistant
##   10B.1d — sanctum apprentices/aspirants (no activity handler; runs in
##            the monthly tick resolver)
##   10B.1e — research_magic (construct target)
##   10B.1f — research_magic (monster target) — per Q19 scope
##
## v1 wave-split tracked in docs/phase-10-plan.md §10B.1 and
## docs/phase-10b-1-handoff.md §6.
##
## Per Q16 [RESOLVED 2026-05-11]: the UI exposes separate launcher cards per
## target type (spell/item/construct/monster) but the backend `research_magic`
## activity row stays unified. Handler dispatch happens inside the
## research_magic handler based on params.project_kind.


static func register_all(registry: ActivityHandlerRegistry) -> void:
	# Phase 10B.1b: spell-side handlers wired. research_magic supports
	# project_kind='spell' (10B.1b) AND project_kind='magic_item' (10B.1c).
	# project_kind='construct' lands in 10B.1e; 'monster' in 10B.1f.
	registry.register("research_magic", ResearchMagicHandler.on_complete)
	registry.register("rewrite_spell",  RewriteSpellHandler.on_complete)
	registry.register("replace_spell",  ReplaceSpellHandler.on_complete)
	registry.register("scribe_spell",   ScribeSpellHandler.on_complete)
	# Phase 10B.1c: L9+ supervise-N-assistants stub. The "+N parallel item
	# creation tasks" effect is documented but the parallel orchestration is
	# deferred to a future polish wave.
	registry.register("manage_assistant", ManageAssistantHandler.on_complete)
