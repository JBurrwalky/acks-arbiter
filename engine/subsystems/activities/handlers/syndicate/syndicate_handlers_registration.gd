class_name SyndicateActivityHandlersRegistration
extends RefCounted

## Registers all 8 syndicate-category activity handlers with an
## ActivityHandlerRegistry. Called once during SessionRunner setup alongside
## DomainActivityHandlersRegistration / FaithActivityHandlersRegistration /
## BardicActivityHandlersRegistration / MagicalResearchActivityHandlersRegistration /
## MercantileActivityHandlersRegistration.
##
## Per Phase 10B.3 UI polish wave + data/activities/syndicate_category.json.
## Mirror of FaithActivityHandlersRegistration.register_all.


static func register_all(registry: ActivityHandlerRegistry) -> void:
	registry.register("order_hijink",      OrderHijinkHandler.on_complete)
	registry.register("plan_hijink",       PlanHijinkHandler.on_complete,
		PlanHijinkHandler.on_tick)
	registry.register("perform_hijink",    PerformHijinkHandler.on_complete)
	registry.register("lay_low",           LayLowHandler.on_complete)
	registry.register("await_trial",       AwaitTrialHandler.on_complete)
	registry.register("bribe_magistrate",  BribeMagistrateHandler.on_complete)
	registry.register("hire_attorney",     HireAttorneyHandler.on_complete)
	registry.register("interplead",        InterpleadHandler.on_complete)
