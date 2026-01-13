# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
mix setup              # Install deps and build assets
mix phx.server         # Start Phoenix server (localhost:4000)
iex -S mix phx.server  # Start with IEx for debugging
mix precommit          # Run before committing: compile --warning-as-errors, deps.unlock --unused, format, test
```

## Testing

```bash
mix test                                    # Run all tests
mix test test/yogan_hockey/anthropic_test.exs  # Run specific test file
mix test --failed                           # Re-run failed tests
mix test --cover                            # Run with coverage
```

GenServers are disabled in test environment (`config :yogan_hockey, start_genservers: false`). Mock adapters in `test/support/`:
- `YoganHockey.HTTP.MockAdapter` - Mock ESPN API responses
- `YoganHockey.HTTP.MockAnthropicAdapter` - Mock Claude AI responses

## Architecture

### Data Flow Pattern

All NHL/DEL2 data follows this pattern:
1. **GenServers** poll external APIs on intervals and cache to ETS
2. **Context modules** (`NHL`, `Playoffs`, `DEL2`) read from ETS cache
3. **LiveViews** subscribe to PubSub topics and re-render on broadcasts

### Key GenServers (lib/yogan_hockey/)

| GenServer | Poll Interval | Purpose |
|-----------|--------------|---------|
| `NHL.LiveScoresServer` | 30s | ESPN live game scores |
| `NHL.TeamsServer` | 5min | Teams and standings |
| `NHL.InjuriesServer` | 1hr | Injury reports |
| `Playoffs.PredictionServer` | 1hr | AI playoff predictions |
| `LiveGames.PredictionServer` | Event-driven | In-game AI predictions |
| `DEL2.YoganStatsServer` | 24hr | Web scraping DEL2 stats |

### ETS Tables

All cached via `YoganHockey.Cache`: `:nhl_live_scores`, `:nhl_teams`, `:nhl_standings`, `:nhl_team_stats`, `:nhl_injuries`, `:player_cache`, `:yogan_stats`, `:playoffs`, `:playoffs_predictions`, `:live_game_predictions`

### PubSub Topics

- `nhl:live_scores`, `nhl:teams`, `nhl:standings`, `nhl:injuries`
- `yogan:stats`
- `playoffs:updates`
- `live_games:predictions`

### HTTP Adapter Pattern

HTTP clients use behaviour-based adapters for testability:
```elixir
# Configure in config/config.exs or config/test.exs
config :yogan_hockey, :http_adapter, YoganHockey.HTTP.ReqAdapter
config :yogan_hockey, :anthropic_adapter, YoganHockey.HTTP.AnthropicHTTPAdapter
```

## Code Organization

- `lib/yogan_hockey/` - Core business logic (contexts, GenServers, API clients)
- `lib/yogan_hockey_web/live/` - Phoenix LiveViews
- `lib/yogan_hockey_web/components/` - Reusable UI components (scoreboard, bracket, standings, player)

### Main Context APIs

```elixir
# NHL data
NHL.list_live_scores()
NHL.list_teams()
NHL.get_team_details(id)
NHL.get_player(id)
NHL.search_players(query)

# Playoffs
Playoffs.get_bracket()
Playoffs.get_playoff_picture()

# AI predictions
Anthropic.predict_live_game_winner(game)
Anthropic.predict_series_outcome(home, away)
```

## Project Guidelines

- Use `:req` (Req) for HTTP requests - avoid HTTPoison, Tesla, httpc
- Use `<.icon name="hero-x-mark">` for icons - never use Heroicons modules directly
- Use `<.input>` component for form inputs from core_components.ex
- LiveView templates must start with `<Layouts.app flash={@flash} ...>`
- Use LiveView streams for collections to avoid memory issues
- Never use deprecated `live_redirect`/`live_patch` - use `<.link navigate={}>` and `push_navigate`
