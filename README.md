# YoganHockey

A real-time NHL statistics and AI-powered predictions application built with Elixir, Phoenix LiveView, and the Anthropic Claude API.

## Features

- **Live NHL Scores**: Real-time game scores with 30-second polling from ESPN's API
- **AI Game Predictions**: Claude-powered win probability predictions for live games
- **Playoff Bracket**: Interactive bracket visualization with AI-predicted advancement probabilities
- **Team Pages**: Detailed team information including rosters, schedules, and statistics
- **Player Search**: Search and favorite NHL players with career statistics
- **Andrew Yogan Stats**: DEL2 hockey statistics tracking with web scraping
- **Easter Eggs**: Hidden player features for personalized content

## Architecture Overview

### GenServers (Background Services)

The application uses several GenServers for autonomous data fetching and caching:

| GenServer | Poll Interval | Purpose |
|-----------|--------------|---------|
| `NHL.LiveScoresServer` | 30 seconds | Fetches live game scores from ESPN |
| `NHL.TeamsServer` | 5 minutes | Maintains team data and standings |
| `DEL2.YoganStatsServer` | 24 hours | Scrapes DEL2 player statistics |
| `Playoffs.PredictionServer` | 5 minutes | Generates AI playoff predictions |
| `LiveGames.PredictionServer` | Event-driven | AI predictions for live games |

### ETS Cache Tables

All data is cached in ETS for fast read access:

| Table | Contents |
|-------|----------|
| `:nhl_live_scores` | Current games and last update timestamp |
| `:nhl_teams` | All 32 NHL teams |
| `:nhl_standings` | Conference/division standings |
| `:nhl_team_stats` | Team details, rosters, and schedules |
| `:player_cache` | Player profiles with career stats |
| `:yogan_stats` | Andrew Yogan statistics |
| `:playoffs` | Playoff bracket and AI predictions |
| `:playoffs_predictions` | Individual series predictions |
| `:live_game_predictions` | AI predictions for active games |

### PubSub Topics

Real-time updates are broadcast via Phoenix PubSub:

| Topic | Events |
|-------|--------|
| `nhl:live_scores` | `:live_scores_updated` |
| `nhl:teams` | `:teams_updated` |
| `nhl:standings` | `:standings_updated` |
| `yogan:stats` | `:yogan_stats_updated`, `:team_schedule_updated` |
| `playoffs:updates` | `:generation_started`, `:playoff_picture_updated`, `:generation_failed` |
| `live_games:predictions` | `:prediction_updated` |

## Project Structure

```
lib/
├── yogan_hockey/                  # Core business logic
│   ├── nhl.ex                     # NHL context (main API)
│   ├── del2.ex                    # DEL2 context
│   ├── playoffs.ex                # Playoffs context
│   ├── anthropic.ex               # Claude AI client
│   ├── cache.ex                   # ETS cache management
│   ├── application.ex             # OTP Application
│   ├── nhl/
│   │   ├── api_client.ex          # ESPN API client
│   │   ├── parsers.ex             # JSON parsing
│   │   ├── live_scores_server.ex  # Live scores GenServer
│   │   └── teams_server.ex        # Teams/standings GenServer
│   ├── del2/
│   │   ├── elite_prospects_scraper.ex
│   │   └── yogan_stats_server.ex
│   ├── playoffs/
│   │   └── prediction_server.ex   # Playoff AI predictions
│   ├── live_games/
│   │   └── prediction_server.ex   # Game AI predictions
│   └── http/
│       ├── adapter.ex             # HTTP behaviour
│       ├── req_adapter.ex         # Req implementation
│       └── anthropic_http_adapter.ex
│
└── yogan_hockey_web/              # Phoenix web layer
    ├── live/
    │   ├── dashboard_live.ex      # Home page
    │   ├── live_scores_live.ex    # Live scores with AI
    │   ├── playoffs_live.ex       # Bracket & predictions
    │   ├── nhl_live.ex            # Standings & teams
    │   ├── team_live.ex           # Team details
    │   ├── players_live.ex        # Player search
    │   ├── player_live.ex         # Player details
    │   └── yogan_live.ex          # Andrew Yogan stats
    ├── components/
    │   ├── core_components.ex     # Base UI components
    │   ├── hockey_components.ex   # Re-exports
    │   ├── scoreboard_components.ex
    │   ├── bracket_components.ex
    │   ├── standings_components.ex
    │   └── player_components.ex
    └── router.ex
```

## Context Modules

### YoganHockey.NHL

Primary interface for NHL data:

```elixir
# Live scores
NHL.list_live_scores()                    # Get current games
NHL.refresh_live_scores()                 # Force refresh from API

# Teams
NHL.list_teams()                          # All 32 teams
NHL.get_team(id)                          # Basic team info
NHL.get_team_details(id)                  # Full team with roster
NHL.get_team_schedule(id)                 # Team schedule

# Players
NHL.get_player(id)                        # Player with career stats
NHL.search_players(query)                 # Search by name

# Standings
NHL.list_standings()                      # Current standings
NHL.refresh_standings()                   # Force refresh
```

### YoganHockey.Playoffs

Playoff bracket and AI predictions:

```elixir
Playoffs.get_bracket()                    # Current bracket structure
Playoffs.get_playoff_picture()            # AI predictions (all teams)
Playoffs.get_prediction(series_id)        # Single series prediction
Playoffs.generate_playoff_picture()       # Force regeneration
```

### YoganHockey.Anthropic

AI prediction interface using Claude:

```elixir
Anthropic.predict_live_game_winner(game)  # In-game win probability
Anthropic.predict_series_outcome(home, away)  # Series prediction
Anthropic.predict_playoff_picture(standings)  # Full bracket prediction
```

## Setup

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 27+
- Node.js 18+ (for assets)

### Environment Variables

Create a `.env` file in the project root:

```bash
# Required for AI predictions
ANTHROPIC_API_KEY=sk-ant-...

# Optional for production
SECRET_KEY_BASE=...
PHX_HOST=your-domain.com
```

### Installation

```bash
# Install dependencies
mix setup

# Start the server
mix phx.server

# Or run in IEx for debugging
iex -S mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to view the application.

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/yogan_hockey/anthropic_test.exs

# Run with coverage
mix test --cover
```

### Test Configuration

GenServers are disabled during tests (`config/test.exs`):

```elixir
config :yogan_hockey, start_genservers: false
```

Mock adapters are provided for HTTP and Anthropic API calls:

- `YoganHockey.HTTP.MockAdapter` - Mock ESPN API responses
- `YoganHockey.HTTP.MockAnthropicAdapter` - Mock AI responses

## Deployment

### Fly.io

The application is configured for deployment on Fly.io:

```bash
fly deploy
```

### Environment Setup

Ensure these secrets are set:

```bash
fly secrets set ANTHROPIC_API_KEY=sk-ant-...
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
```

## Design Decisions

### Why ETS?

ETS is appropriate for this application because:

1. **Read-heavy workload**: LiveViews frequently read cached data
2. **Single-node deployment**: No distributed state coordination needed
3. **Ephemeral data**: All data can be refetched from APIs
4. **Performance**: `:read_concurrency` option optimizes concurrent reads

### GenServer Patterns

- **Non-blocking callbacks**: Long operations run in supervised tasks
- **Exponential backoff**: Failed requests retry with increasing delays
- **PubSub broadcasting**: Decouples data fetching from UI updates

### Adapter Pattern

HTTP clients use behaviour-based adapters for testability:

```elixir
# Behaviour
defmodule YoganHockey.HTTP.Adapter do
  @callback get_json(url, headers, opts) :: {:ok, map()} | {:error, term()}
end

# Configure adapter
config :yogan_hockey, :http_adapter, YoganHockey.HTTP.ReqAdapter
```

## API Data Sources

| Source | Data | Rate Limits |
|--------|------|-------------|
| ESPN API | Games, teams, standings, players | ~1 req/second |
| Elite Prospects | DEL2 player stats | ~1 req/minute |
| HockeyDB | Career statistics | ~1 req/minute |
| Anthropic Claude | AI predictions | Per API plan |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass: `mix test`
5. Submit a pull request

## License

This project is for educational purposes. NHL data is provided by ESPN's public API.
