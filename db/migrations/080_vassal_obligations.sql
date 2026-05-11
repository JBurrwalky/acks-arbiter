-- Migration 080: vassal_obligations — Phase 8 Favors & Duties Monthly System
--
-- Per docs/domain-roadmap-corrected.md Phase 8 + acore_axioms_strongholds_and_domains.xml
-- §favors_and_duties L352-372.
--
-- Each row records one favor or duty issued from a liege to a vassal. Both
-- ongoing and one-time obligations are stored; one-time obligations are
-- inserted with status='completed' immediately after their effect executes
-- (gift treasury transfer, etc.).
--
-- kind:
--   favor — granted to vassal (charter_of_monopoly / gift / office /
--           troops / grant_of_land per RAW L367-371)
--   duty  — demanded of vassal (construction / scutage / call_to_council /
--           call_to_arms / loan per RAW L361-365)
--
-- type matches the RAW result key (snake_case): construction, scutage,
-- call_to_council, call_to_arms, loan, charter_of_monopoly, gift, office,
-- troops, grant_of_land.
--
-- magnitude (integer): per-RAW magnitude. Examples:
--   construction: total expenditure target gp (15000 × hex_count in realm)
--   scutage:      monthly gp_value (1 × realm_families)
--   call_to_arms: monthly wages gp (1 × realm_families)
--   loan:         loan principal gp (1 × realm_families)
--   gift:         gp transferred (1 × realm_families)
--
-- gp_value (integer): cumulative gp moved by this obligation. For
-- one-time obligations (gift, grant_of_land), this is the issue-day amount.
-- For ongoing duties (scutage, loan repayment), this is the running total.
--
-- status:
--   active     — currently in force
--   revoked    — RAW L366: revocation roll consumed it
--   completed  — one-time effect executed (gift, grant_of_land)
--   defaulted  — vassal couldn't fulfill (e.g., couldn't pay scutage)
--
-- loyalty_modifier_applied (integer): if this obligation was issued at a
-- duty count exceeding the safe-duty threshold, this records the cumulative
-- -N penalty applied to the henchman-loyalty roll at issue. 0 = within safe
-- threshold (no penalty applied).

CREATE TABLE IF NOT EXISTS vassal_obligations (
    id                          TEXT    PRIMARY KEY,
    vassal_assignment_id        TEXT    NOT NULL REFERENCES vassal_assignments(id),
    kind                        TEXT    NOT NULL
        CHECK(kind IN ('favor', 'duty')),
    type                        TEXT    NOT NULL,
    magnitude                   INTEGER NOT NULL DEFAULT 0,
    gp_value                    INTEGER NOT NULL DEFAULT 0,
    is_one_time                 INTEGER NOT NULL DEFAULT 0
        CHECK(is_one_time IN (0, 1)),
    issued_calendar_day         INTEGER NOT NULL DEFAULT 0,
    due_calendar_day            INTEGER NOT NULL DEFAULT 0,
    status                      TEXT    NOT NULL DEFAULT 'active'
        CHECK(status IN ('active', 'revoked', 'completed', 'defaulted')),
    loyalty_modifier_applied    INTEGER NOT NULL DEFAULT 0,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_vassal_obligations_assignment
    ON vassal_obligations(vassal_assignment_id);

CREATE INDEX IF NOT EXISTS idx_vassal_obligations_kind
    ON vassal_obligations(vassal_assignment_id, kind, status);

CREATE INDEX IF NOT EXISTS idx_vassal_obligations_status
    ON vassal_obligations(status);
