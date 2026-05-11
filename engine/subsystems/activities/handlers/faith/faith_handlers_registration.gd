class_name FaithActivityHandlersRegistration
extends RefCounted

## Registers all 8 divine-category activity handlers with an
## ActivityHandlerRegistry. Called once during SessionRunner setup, alongside
## DomainActivityHandlersRegistration.
##
## Per Phase 10A.2 + gdd-domain-tab.md §12.2 Faith block. Mirror of
## DomainActivityHandlersRegistration.register_all.


static func register_all(registry: ActivityHandlerRegistry) -> void:
	registry.register("dispatch_missionaries",      DispatchMissionariesHandler.on_complete)
	registry.register("cast_charitable_spells",     CastCharitableSpellsHandler.on_complete)
	registry.register("consecrate_altar",           ConsecrateAltarHandler.on_complete)
	registry.register("consecrate_fields",          ConsecrateFieldsHandler.on_complete)
	registry.register("consecrate_ruler",           ConsecrateRulerHandler.on_complete)
	registry.register("extract_divine_power",       ExtractDivinePowerHandler.on_complete)
	registry.register("perform_blood_sacrifice",    PerformBloodSacrificeHandler.on_complete)
	registry.register("perform_ceremonial_sacrifice", PerformCeremonialSacrificeHandler.on_complete)
