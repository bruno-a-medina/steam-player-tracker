-- Steam Player-Count Tracker: analysis queries
-- Table: player_counts(id, app_id, player_count, timestamp)
-- Run these one at a time. Query 0 creates the helper objects the others use.
--
-- The collection has a pause in it (the scheduled workflow stopped for a while),
-- so the rolling and week-over-week queries use calendar days, not row counts.
-- A row-based window would quietly compare today with weeks-old data.


-- 0. Setup: one row per game per day, plus readable game names.
--    Add names for any app_id you want labeled. Unlisted games show their ID.
CREATE OR REPLACE VIEW daily_player_counts AS
SELECT
    app_id,
    DATE_TRUNC('day', timestamp)::date AS day,
    AVG(player_count)                  AS players
FROM player_counts
GROUP BY app_id, DATE_TRUNC('day', timestamp)::date;

CREATE OR REPLACE VIEW game_names AS
SELECT app_id, name FROM (VALUES
    (1172470, 'Apex Legends'),
    (2767030, 'Marvel Rivals'),
    (2357570, 'Overwatch 2'),
    (872200,  'Rogue Company'),
    (2073850, 'THE FINALS'),
    (291550,  'Brawlhalla'),
    (1237950, 'STAR WARS Battlefront II')
) AS t(app_id, name);


-- 1. Coverage: days of data per game, and the first and last day.
SELECT
    COALESCE(g.name, d.app_id::text) AS game,
    COUNT(*)  AS days_of_data,
    MIN(day)  AS first_day,
    MAX(day)  AS last_day
FROM daily_player_counts d
LEFT JOIN game_names g USING (app_id)
GROUP BY COALESCE(g.name, d.app_id::text)
ORDER BY game;


-- 2. 7-day rolling average per game (calendar days).
SELECT
    COALESCE(g.name, d.app_id::text) AS game,
    d.day,
    ROUND(d.players) AS players,
    ROUND(AVG(d.players) OVER (
        PARTITION BY d.app_id
        ORDER BY d.day
        RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW
    )) AS rolling_7d_avg
FROM daily_player_counts d
LEFT JOIN game_names g USING (app_id)
ORDER BY game, d.day;


-- 3. Week-over-week % change (only where the day 7 days earlier exists).
WITH lagged AS (
    SELECT
        app_id,
        day,
        players,
        LAG(players, 7) OVER w AS players_7_rows_back,
        LAG(day, 7)     OVER w AS day_7_rows_back
    FROM daily_player_counts
    WINDOW w AS (PARTITION BY app_id ORDER BY day)
)
SELECT
    COALESCE(g.name, l.app_id::text) AS game,
    l.day,
    ROUND(l.players)             AS players,
    ROUND(l.players_7_rows_back) AS players_7d_ago,
    ROUND(100.0 * (l.players - l.players_7_rows_back)
          / NULLIF(l.players_7_rows_back, 0), 1) AS wow_pct_change
FROM lagged l
LEFT JOIN game_names g USING (app_id)
WHERE l.day - l.day_7_rows_back = 7
ORDER BY game, l.day;


-- 4. 7-day volatility: standard deviation divided by the mean, so large and
--    small games can be compared. Higher means a more unstable week.
SELECT
    COALESCE(g.name, d.app_id::text) AS game,
    d.day,
    ROUND(
        (STDDEV(d.players) OVER w / NULLIF(AVG(d.players) OVER w, 0))::numeric,
        3
    ) AS rolling_7d_volatility
FROM daily_player_counts d
LEFT JOIN game_names g USING (app_id)
WINDOW w AS (
    PARTITION BY d.app_id
    ORDER BY d.day
    RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW
)
ORDER BY game, d.day;


-- 5. Popularity rank over everything collected so far.
SELECT
    COALESCE(g.name, d.app_id::text)               AS game,
    ROUND(AVG(d.players))                          AS avg_players,
    MAX(ROUND(d.players))                          AS peak_daily_sample,
    RANK() OVER (ORDER BY AVG(d.players) DESC)     AS popularity_rank
FROM daily_player_counts d
LEFT JOIN game_names g USING (app_id)
GROUP BY COALESCE(g.name, d.app_id::text)
ORDER BY popularity_rank;
