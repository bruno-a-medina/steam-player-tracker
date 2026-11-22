-- Steam Player-Count Tracker: analysis queries
-- Assumes a table player_counts(app_id, player_count, timestamp)
-- as written by steam_tracker.py. Adjust names if your schema differs.

-- Base view: one row per game per day.
-- Averaging guards against the workflow running twice in a day.
CREATE OR REPLACE VIEW daily_player_counts AS
SELECT
    app_id,
    DATE_TRUNC('day', timestamp)::date AS day,
    AVG(player_count)                  AS players
FROM player_counts
GROUP BY app_id, DATE_TRUNC('day', timestamp)::date;


-- 1. 7-day rolling average per game
SELECT
    app_id,
    day,
    players,
    AVG(players) OVER (
        PARTITION BY app_id
        ORDER BY day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS rolling_7d_avg
FROM daily_player_counts
ORDER BY app_id, day;


-- 2. Week-over-week % change (today vs the same weekday last week)
SELECT
    app_id,
    day,
    players,
    LAG(players, 7) OVER (PARTITION BY app_id ORDER BY day) AS players_7d_ago,
    ROUND(
        100.0 * (players - LAG(players, 7) OVER (PARTITION BY app_id ORDER BY day))
        / NULLIF(LAG(players, 7) OVER (PARTITION BY app_id ORDER BY day), 0),
        1
    ) AS wow_pct_change
FROM daily_player_counts
ORDER BY app_id, day;


-- 3. 7-day rolling volatility, scaled by the rolling mean
--    (coefficient of variation, so big and small games are comparable)
SELECT
    app_id,
    day,
    ROUND(
        STDDEV(players) OVER w / NULLIF(AVG(players) OVER w, 0),
        3
    ) AS rolling_7d_cv
FROM daily_player_counts
WINDOW w AS (
    PARTITION BY app_id
    ORDER BY day
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
)
ORDER BY app_id, day;


-- 4. Rank games by average players over the last 30 days
SELECT
    app_id,
    ROUND(AVG(players)) AS avg_players_30d,
    RANK() OVER (ORDER BY AVG(players) DESC) AS popularity_rank
FROM daily_player_counts
WHERE day >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY app_id
ORDER BY popularity_rank;
