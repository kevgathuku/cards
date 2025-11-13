defmodule Kadi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KadiWeb.Telemetry,
      Kadi.Repo,
      {DNSCluster, query: Application.get_env(:kadi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Kadi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Kadi.Finch},
      {Kadi.Games.Supervisor, name: Kadi.Games.Supervisor},
      # Start to serve requests, typically the last entry
      KadiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Kadi.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Attach telemetry handlers for King feature
    :telemetry.attach_many(
      "king-card-telemetry",
      [
        [:kadi, :king, :direction_change],
        [:kadi, :king, :cardless_entered],
        [:kadi, :king, :anomaly_skip]
      ],
      &handle_king_telemetry/4,
      nil
    )

    # Attach telemetry handlers for Jack feature
    :telemetry.attach_many(
      "jack-card-telemetry",
      [
        [:kadi, :jack, :skip_executed],
        [:kadi, :jack, :cardless_entered]
      ],
      &handle_jack_telemetry/4,
      nil
    )

    # Attach telemetry handlers for Ace feature
    :telemetry.attach_many(
      "ace-card-telemetry",
      [
        [:kadi, :ace, :suit_selected]
      ],
      &handle_ace_telemetry/4,
      nil
    )

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KadiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Handles telemetry events for King card feature.
  #
  # Logs all King-related events (direction_change, cardless_entered, anomaly_skip)
  # with their metadata for observability.
  defp handle_king_telemetry(event, _measurements, metadata, _config) do
    require Logger
    event_name = Enum.join(event, ".")
    Logger.info("#{event_name}: #{inspect(metadata)}")
  end

  # Handles telemetry events for Jack card feature.
  #
  # Logs all Jack-related events (skip_executed, cardless_entered)
  # with their metadata for observability.
  defp handle_jack_telemetry(event, _measurements, metadata, _config) do
    require Logger
    event_name = Enum.join(event, ".")
    Logger.info("#{event_name}: #{inspect(metadata)}")
  end

  # Handles telemetry events for Ace card feature.
  #
  # Logs all Ace-related events (suit_selected)
  # with their metadata for observability.
  defp handle_ace_telemetry(event, _measurements, metadata, _config) do
    require Logger
    event_name = Enum.join(event, ".")
    Logger.info("#{event_name}: #{inspect(metadata)}")
  end
end
