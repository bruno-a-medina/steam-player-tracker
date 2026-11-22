# Steam Player-Count Tracker

An automated pipeline that records how many people are playing a set of competitive games on Steam, once a day, and stores the history in Postgres so it can be analyzed as a time series.

![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=githubactions&logoColor=white)

## Why I built it

I wanted a small project that runs on its own, with no laptop involved, and produces a real time series I could use to practice SQL window functions. Daily player counts behave like daily active users or demand for a product: trends, weekly seasonality, and sudden drops after a patch or a competitor launch. The same shape of problem shows up in revenue and demand forecasting.

## How it works

```
Steam Web API  ->  Python script  ->  Postgres (Neon)  ->  SQL analysis
                        ^
                GitHub Actions (daily, 12:00 UTC)
```

1. **Ingest.** `steam_tracker.py` calls Steam's `GetNumberOfCurrentPlayers` endpoint for 7 games (Apex Legends, Marvel Rivals, Overwatch 2, and four others).
2. **Store.** Each run inserts one timestamped row per game into a Postgres table hosted on Neon. The connection string lives in a `DATABASE_URL` secret, never in the code.
3. **Schedule.** A GitHub Actions workflow runs the script every day at 12:00 UTC, so the history keeps growing without any manual step.
4. **Analyze.** `analysis.sql` holds the window-function queries listed below.

## Analysis queries

All in [`analysis.sql`](analysis.sql):

| Query | Window function used |
|---|---|
| 7-day rolling average per game | `AVG() OVER (PARTITION BY app_id ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` |
| Week-over-week % change | `LAG(..., 7) OVER (PARTITION BY app_id ORDER BY day)` |
| 7-day rolling volatility | `STDDEV() OVER (...)` |
| Rank of games by average players | `RANK() OVER (ORDER BY avg_players DESC)` |

## Run it yourself

```bash
git clone https://github.com/98bruno89-eng/steam-player-tracker.git
cd steam-player-tracker
pip install -r requirements.txt
echo "DATABASE_URL=postgresql://user:password@host/dbname" > .env
python steam_tracker.py
```

You need a Postgres database with a `player_counts` table. The expected shape is in [`schema.sql`](schema.sql).

## Known limitations

- **One snapshot per day.** Each row is the player count at roughly 12:00 UTC, not the daily peak or average, so the numbers are a sample of the day rather than a full measure of it.
- **No retry or alerting yet.** A failed API call fails that day's run. The Actions log shows it, but nothing notifies me.
- **Games are hardcoded.** The 7 app IDs live in the script rather than in a config file or table.

## What I would add next

- Retry with backoff and a clear error message when Steam does not respond
- A failed-run alert (GitHub Actions notification or email)
- A dashboard on top of the rolling averages
- Event flags for patch days and seasons, to check how much they move the counts

## Tech

Python (`requests`, `psycopg2`, `python-dotenv`), PostgreSQL on Neon, GitHub Actions, SQL window functions.
