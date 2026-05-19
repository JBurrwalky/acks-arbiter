-- Migration 112: rename troop_units monthly_*_gp money columns to _cp + scale × 100.
--
-- Per the 2026-05-15 currency-precision rule + the Phase 5 garrison wiring
-- that lands in the 2026-05-16 session: troop wages flow into the domain
-- treasury via the monthly tick's expense calculator. To keep "seamless
-- accounting" — no gp/cp boundary conversions inside the money flow —
-- the troop_units cost columns become cp-native here.
--
-- Columns:
--   troop_units.monthly_wage_gp        → monthly_wage_cp        (× 100)
--   troop_units.monthly_supply_gp      → monthly_supply_cp      (× 100)
--   troop_units.monthly_specialist_gp  → monthly_specialist_cp  (× 100)
--   troop_units.monthly_cost_gp        → monthly_cost_cp        (× 100)
--
-- Existing rows scale by 100 so the gp magnitudes that were paid before this
-- migration continue paying the same money under the cp interpretation.

BEGIN TRANSACTION;

ALTER TABLE troop_units RENAME COLUMN monthly_wage_gp TO monthly_wage_cp;
UPDATE troop_units SET monthly_wage_cp = monthly_wage_cp * 100;

ALTER TABLE troop_units RENAME COLUMN monthly_supply_gp TO monthly_supply_cp;
UPDATE troop_units SET monthly_supply_cp = monthly_supply_cp * 100;

ALTER TABLE troop_units RENAME COLUMN monthly_specialist_gp TO monthly_specialist_cp;
UPDATE troop_units SET monthly_specialist_cp = monthly_specialist_cp * 100;

ALTER TABLE troop_units RENAME COLUMN monthly_cost_gp TO monthly_cost_cp;
UPDATE troop_units SET monthly_cost_cp = monthly_cost_cp * 100;

COMMIT;
