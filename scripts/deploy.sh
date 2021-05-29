#!/bin/bash
git pull origin master
mix deps.get
MIX_ENV=prod mix compile

# Assets
(cd assets/ && npm ci && npm run deploy)
MIX_ENV=prod mix phx.digest

echo "Restarting server..."
(sudo lsof -ti :4000 | xargs kill) || true
MIX_ENV=prod mix ecto.migrate
PORT=4000 MIX_ENV=prod elixir --erl "-detached" -S mix phx.server --no-compile
echo "Server restarted!"
