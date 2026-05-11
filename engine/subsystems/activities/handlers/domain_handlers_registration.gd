class_name DomainActivityHandlersRegistration
extends RefCounted

## Registers all 16 domain-category activity handlers with an
## ActivityHandlerRegistry. Called once during SessionRunner setup.
##
## Mapping mirrors data/activities/domain_category.json. Phase 5/9 will add
## additional category handlers (troops, faith, magical, etc.) by adding
## sibling registration files.


static func register_all(registry: ActivityHandlerRegistry) -> void:
	registry.register("administer_domain",       AdministerDomainHandler.on_complete)
	registry.register("issue_decree",            IssueDecreeHandler.on_complete)
	registry.register("manage_henchmen",         ManageHenchmenHandler.on_complete)
	registry.register("conscript_troops",        ConscriptTroopsHandler.on_complete)
	registry.register("levy_militia",            LevyMilitiaHandler.on_complete)
	registry.register("solicit_mercenaries",     SolicitMercenariesHandler.on_complete)
	registry.register("call_to_arms",            CallToArmsHandler.on_complete)
	registry.register("oversee_investment",      OverseeInvestmentHandler.on_complete)
	registry.register("hire_mercenaries",        HireMercenariesHandler.on_complete)
	registry.register("inspect_troops",          InspectTroopsHandler.on_complete)
	registry.register("train_troops",            TrainTroopsHandler.on_complete)
	registry.register("oversee_troop_training",  OverseeTroopTrainingHandler.on_complete)
	registry.register("oversee_construction",    OverseeConstructionHandler.on_complete)
	registry.register("supervise_construction",  SuperviseConstructionHandler.on_complete)
	registry.register("military_campaign",       MilitaryCampaignHandler.on_complete)
	registry.register("repress_population",      RepressPopulationHandler.on_complete)
