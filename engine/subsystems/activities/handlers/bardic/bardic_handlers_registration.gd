class_name BardicActivityHandlersRegistration
extends RefCounted

## Registers Bard-only activity handlers with an ActivityHandlerRegistry.
## Phase 10A.3, per Q14 [RESOLVED 2026-05-11]. Currently a single launchable
## activity (solicit_followers); chronicles_of_battle is a passive ability
## (not registered as an activity handler).


static func register_all(registry: ActivityHandlerRegistry) -> void:
	registry.register("solicit_followers", SolicitFollowersHandler.on_complete)
