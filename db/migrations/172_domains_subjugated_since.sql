-- Migration 172: domains.subjugated_since_tick — how long a runtime domain's realm
-- has been under its overlord. The setting→runtime materializer sets it on each
-- war-vassal crown to the tick of the latest vassalage/conquest/protectorate event
-- that subjugated its polity; -1 = never subjugated (a sovereign / independent realm).
-- NPCs + the LLM narrator key on subjugation duration (a recently-conquered realm
-- chafes; an old one has settled) — gdd-setting-runtime-materialization §15.3 /
-- principle 3. Behavior wiring is deferred to M5; this preserves the data.
ALTER TABLE domains ADD COLUMN subjugated_since_tick INTEGER NOT NULL DEFAULT -1;
