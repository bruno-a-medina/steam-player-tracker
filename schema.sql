-- Expected shape of the table steam_tracker.py writes to.
-- Check it against your Neon database before relying on it:
--   \d player_counts
CREATE TABLE IF NOT EXISTS player_counts (
    id           SERIAL PRIMARY KEY,
    app_id       INTEGER NOT NULL,
    player_count INTEGER NOT NULL,
    timestamp    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_player_counts_app_time
    ON player_counts (app_id, timestamp);
