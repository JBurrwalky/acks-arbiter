class_name CampaignCreationState
extends SessionState

## Hosts the pre-game setting-generation UI (the campaign-creation flow:
## gdd-campaign-creation-ui.md). Reached from campaign-select's "Generate New
## World". On approval the flow has already locked the world; we return to
## campaign select for now.
##
## The flow is a CanvasLayer added DIRECTLY to Main (not pushed onto the
## NavigationStack) — same as PartyCreationState — because the nav stack is still
## mid-transition from the campaign-select pop, so a push_node would be dropped.
##
## On approval the flow has locked the world; M3 then MATERIALIZES it (setting_* →
## runtime domains/settlements/realms/play-map) so the generated campaign is
## playable, and returns to campaign select where the player picks it → party
## creation → SessionLoadState (which lands the party on the 6-mile play map). The
## start city is auto-picked for now (the Decision-K picker is a follow-up).

var _flow: Node = null


func enter(runner, _context: Dictionary) -> void:
	var scene: PackedScene = preload(
		"res://scenes/ui/campaign_creation/campaign_creation_flow.tscn")
	_flow = scene.instantiate()
	_flow.campaign_ready.connect(
		func(campaign_id: String):
			# M3: materialize the locked generated world into the runtime tables.
			var res: Dictionary = SettingMaterializer.new().materialize(campaign_id, "")
			if not bool(res.get("ok", false)):
				push_error("CampaignCreationState: materialization failed: %s" % str(res.get("errors", [])))
			runner.submit_action("world_ready", {"campaign_id": campaign_id})
	)
	runner.get_parent().add_child(_flow)


func exit(_runner) -> void:
	if _flow != null and is_instance_valid(_flow):
		_flow.queue_free()
	_flow = null


func handle_action(_runner, action: String, _payload: Dictionary) -> String:
	if action == "world_ready" or action == "cancel_creation":
		return "campaign_select"
	return ""
