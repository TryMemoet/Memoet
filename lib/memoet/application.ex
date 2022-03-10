defmodule Memoet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    maybe_run_migrations()

    children = [
      # Start the Ecto repository
      Memoet.Repo,
      # Start the Telemetry supervisor
      MemoetWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Memoet.PubSub},
      # Start the Endpoint (http/https)
      # {SiteEncrypt.Phoenix, MemoetWeb.Endpoint},
      MemoetWeb.Endpoint,
      # Cache
      {Cachex, name: :memoet_cachex},
      # Job
      {Oban, oban_config()},
      # Pow delete expired token
      {Pow.Postgres.Store.AutoDeleteExpired, [interval: :timer.hours(1)]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Memoet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MemoetWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    Application.get_env(:memoet, Oban)
  end

  defp maybe_run_migrations() do
    unless Application.get_env(:memoet, :skip_migrations) do
      Memoet.ReleaseTasks.init()
    end
  end
end
