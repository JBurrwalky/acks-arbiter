class_name CampaignSelectState
extends SessionState

## Displays the campaign selection screen and waits for the player to
## select or create a campaign.

var _select_node: Node = null


func enter(runner, context: Dictionary) -> void:
	var scene: PackedScene = preload(
		"res://scenes/ui/campaign_select/campaign_select_screen.tscn"
	)
	_select_node = scene.instantiate()
	_select_node.campaign_selected.connect(
		func(campaign_id: String):
			runner.submit_action("campaign_selected", {"campaign_id": campaign_id})
	)
	_select_node.campaign_created.connect(
		func(campaign_id: String):
			runner.submit_action("campaign_created", {"campaign_id": campaign_id})
	)
	_select_node.create_world_requested.connect(
		func():
			runner.submit_action("create_world", {})
	)
	runner.get_nav_stack().push_node(_select_node, "campaign_select")


func exit(runner) -> void:
	runner.get_nav_stack().pop()
	_select_node = null


func handle_action(runner, action: String, payload: Dictionary) -> String:
	if action == "campaign_selected":
		return "session_load"
	if action == "campaign_created":
		return "party_creation"
	if action == "create_world":
		return "campaign_creation"
	return ""
