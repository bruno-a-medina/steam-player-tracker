# Steam Player-Count Tracker

**Question:** how do player counts for popular competitive games change from day to day and week to week?

This pipeline records the current player count for seven Steam games once a day and stores the history in Postgres. SQL window functions turn that history into rolling averages, week-over-week change and volatility.

## Results

63 days of data per game, collected between Jul 13 and Nov 23, 2026. The scheduled run was paused from Sep 13 to Nov 22, so the analysis uses calendar-day windows rather than row counts.

| Rank | Game | Average players | Highest daily sample | Avg 7-day volatility |
|---|---|---|---|---|
| 1 | Apex Legends | 199,524 | 286,600 | 0.181 |
| 2 | Marvel Rivals | 62,846 | 126,219 | 0.139 |
| 3 | Overwatch 2 | 57,975 | 77,445 | 0.061 |
| 4 | THE FINALS | 11,734 | 17,781 | 0.127 |
| 5 | Brawlhalla | 9,681 | 14,361 | 0.086 |
| 6 | STAR WARS Battlefront II | 1,261 | 1,596 | 0.108 |
| 7 | Rogue Company | 181 | 270 | 0.120 |

- **Scale varies a lot.** Apex Legends averaged about 3x the players of Marvel Rivals, and 1,100x the players of Rogue Company.
- **Overwatch 2 was the steadiest.** Its volatility of 0.061 was the lowest of the seven, and Apex Legends was the highest at 0.181. Volatility here is the standard deviation divided by the mean over a rolling 7-day window, so large and small games are comparable.
- **Marvel Rivals has the widest gap between its average and its highest sample.** Its highest daily sample (126,219) is about twice its average, compared with 1.3x for Overwatch 2.

Queries are in [`analysis.sql`](analysis.sql).

## How it works

```
Steam Web API  ->  steam_tracker.py  ->  Postgres (Neon)  ->  analysis.sql
                         ^
               GitHub Actions (daily, 12:00 UTC)
```

1. **Ingest.** `steam_tracker.py` calls Steam's `GetNumberOfCurrentPlayers` endpoint for each game.
2. **Store.** Each run inserts one timestamped row per game. The connection string is a GitHub secret (`DATABASE_URL`), never committed.
3. **Schedule.** A GitHub Actions workflow runs the script every day, so the history grows without manual work.
4. **Analyze.** [`analysis.sql`](analysis.sql) holds the queries below. [`schema.sql`](schema.sql) shows the expected table.

## Analysis

| Query | Window function |
|---|---|
| 7-day rolling average per game | `AVG() OVER (... RANGE BETWEEN INTERVAL '6 days' PRECEDING AND CURRENT ROW)` |
| Week-over-week % change | `LAG(players, 7) OVER (...)`, kept only where the earlier day is exactly 7 days back |
| 7-day volatility (coefficient of variation) | `STDDEV() / AVG() OVER (...)` |
| Popularity rank over the whole collection | `RANK() OVER (ORDER BY avg DESC)` |

## Run it yourself

```bash
git clone https://github.com/bruno-a-medina/steam-player-tracker.git
cd steam-player-tracker
pip install -r requirements.txt
echo "DATABASE_URL=postgresql://user:password@host/dbname" > .env
python steam_tracker.py
```

Create the table with `schema.sql` first. The script needs a `.env` file or the `DATABASE_URL` environment variable.

## Limitations

- **One snapshot per day.** Each row is the count at about 12:00 UTC, not the daily peak or average.
- **Scheduled runs can pause.** GitHub disables scheduled workflows after 60 days without a commit to the repo. This one stopped for a stretch and was switched back on, so the data has a gap. The analysis queries use calendar days so the gap doesn't distort them.
- **No retry or alerting.** A failed API call fails that day's run. The Actions log shows it, but nothing sends a notification.
- **Game list is hardcoded.** The seven app IDs live in `steam_tracker.py`.

## Next steps

- Retry with backoff when Steam doesn't respond
- A failure alert
- A dashboard on top of the rolling averages
- Flags for patch days, to test how much updates move player counts

## Tech

Python (`requests`, `psycopg2`, `python-dotenv`), PostgreSQL on Neon, GitHub Actions, SQL window functions.
