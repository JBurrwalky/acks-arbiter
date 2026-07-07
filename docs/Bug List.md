Bug List

1: Encounter Parley screen has no exit, leave button does nothing or at least doesn't dismiss the layer. Esc key removes exploration HUD. 

2: E 10:29:57:560   roll_monthly_encounters_for_domain: Invalid call 'String' constructor: city_grass_scrub_settled
  <GDScript Source>domain_encounter_resolver.gd:158 @ roll_monthly_encounters_for_domain()
  <Stack Trace>  domain_encounter_resolver.gd:158 @ roll_monthly_encounters_for_domain()
                 domain_handlers.gd:403 @ _resolve_domain_month()
                 domain_handlers.gd:146 @ _handle_monthly_tick()
                 event_handler_registry.gd:86 @ resolve()
                 scheduler_loop.gd:354 @ _resolve_next_event()
                 scheduler_loop.gd:294 @ _tick_normal()
                 scheduler_loop.gd:251 @ tick()
                 session_runner.gd:392 @ _process()


3: 6-mile hex map window does not roll and generate further hexes.

4: camp screen has no watch selection to choose characters for watch. Reccomend a drag-and-drop sysytem with party + henchmen protraits. Also crashes on selecting begin rest: 
E 0:30:44:625   CampHandlers._handle_rest_complete: Invalid call. Nonexistent function 'load_character' in base 'Node (campaign_repository.gd)'.
  <GDScript Source>camp_handlers.gd:226 @ CampHandlers._handle_rest_complete()
  <Stack Trace> camp_handlers.gd:226 @ _handle_rest_complete()
                event_handler_registry.gd:86 @ resolve()
                scheduler_loop.gd:354 @ _resolve_next_event()
                scheduler_loop.gd:327 @ _tick_max_speed()
                scheduler_loop.gd:249 @ tick()
                session_runner.gd:392 @ _process()
