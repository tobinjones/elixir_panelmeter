defmodule Panelmeter.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: Panelmeter.PubSub},
        {Panelmeter.MeterEvents,
         name: Panelmeter.MeterEvents,
         pubsub: Panelmeter.PubSub,
         line_topic: "admx3652:lines",
         reading_topic: "admx3652:readings"}
      ] ++ target_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Panelmeter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # List all child processes to be supervised
  if Mix.target() == :host do
    defp target_children() do
      [
        # Children that only run on the host during development or test.
        # In general, prefer using `config/host.exs` for differences.
        #
        # Starts a worker by calling: Host.Worker.start_link(arg)
        # {Host.Worker, arg},
      ]
    end
  else
    defp target_children() do
      meter =
        case Application.fetch_env(:panelmeter, :admx3652) do
          {:ok, opts} -> [{ADMX3652, opts}]
          :error -> []
        end

      # Distribution starts libcluster into this supervisor once eth0 has an
      # address and the node has a name. See Panelmeter.Distribution.
      meter ++
        [
          {DynamicSupervisor, strategy: :one_for_one, name: Panelmeter.ClusterSupervisor},
          Panelmeter.Distribution
        ]
    end
  end
end
