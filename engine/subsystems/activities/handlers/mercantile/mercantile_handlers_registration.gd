class_name MercantileActivityHandlersRegistration
extends RefCounted

## Registers all 6 mercantile-category activity handlers with an
## ActivityHandlerRegistry. Called once during SessionRunner setup alongside
## DomainActivityHandlersRegistration / FaithActivityHandlersRegistration /
## etc.
##
## Per Phase 10B.2 + gdd-phase-10b-2-trade-block.md §1.4. Mirror of
## FaithActivityHandlersRegistration.register_all.
##
## Wave 10B.2.2 ships:
##   * buy_merchandise — REAL (BuyMerchandiseHandler.on_complete)
##   * sell_merchandise — REAL (SellMerchandiseHandler.on_complete)
##   * persuade_merchants — STUB (replaced in Wave 10B.2.3)
##   * solicit_merchants — STUB (replaced in Wave 10B.2.3; ongoing → on_tick)
##   * locate_merchandise — STUB (replaced in Wave 10B.2.3)
##   * accept_shipping_contract — STUB (replaced in Wave 10B.2.4)


static func register_all(registry: ActivityHandlerRegistry) -> void:
	registry.register("buy_merchandise",          BuyMerchandiseHandler.on_complete)
	registry.register("sell_merchandise",         SellMerchandiseHandler.on_complete)
	registry.register("persuade_merchants",       PersuadeMerchantsHandler.on_complete)
	registry.register("solicit_merchants",        SolicitMerchantsHandler.on_complete,
		SolicitMerchantsHandler.on_tick)
	registry.register("locate_merchandise",       LocateMerchandiseHandler.on_complete)
	registry.register("accept_shipping_contract", AcceptShippingContractHandler.on_complete)
	# Phase 10B.2 Wave 3: forfeit router subscribes to EventBus.activity_forfeited
	# to dispatch terminal-forfeit cleanup to per-activity handlers (currently
	# just solicit_merchants's unfired-reveal rollback per §5.4). Idempotent.
	MercantileForfeitRouter.register_signal_listeners()
