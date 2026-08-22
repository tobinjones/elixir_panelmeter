defmodule ADMX3652 do
  @moduledoc """
  Driver for an ADMX3652 panel meter.

  This module provides the public API for starting and controlling a meter.
  """

  alias ADMX3652.{Command, StateMachine}

  @doc """
  Enables the instrument.

  From `:off`, a successful request enters `:starting`. The driver enters
  `:configuring` when the instrument reports that it is ready, applies the
  startup configuration, and enters `:ready` with a complete shadow. Startup
  or configuration failures enter `:desynchronised`.
  """
  @spec enable(:gen_statem.server_ref()) :: :ok | {:error, term()}
  def enable(meter) do
    :gen_statem.call(meter, :enable, :infinity)
  end

  @doc """
  Disables the instrument, interrupting any active exchange.

  A successful request enters `:off`. If the transport fails, the driver
  enters `:desynchronised` instead.
  """
  @spec disable(:gen_statem.server_ref()) :: :ok | {:error, term()}
  def disable(meter) do
    :gen_statem.call(meter, :disable, :infinity)
  end

  @doc """
  Reads the currently resolved range for a channel.
  """
  @spec get_range(:gen_statem.server_ref(), ADMX3652.Protocol.channel()) ::
          {:ok, float()} | {:error, term()}
  def get_range(meter, channel) when channel in [1, 2] do
    :gen_statem.call(meter, {:get_range, channel}, :infinity)
  end

  @doc """
  Sets the configured range for a channel.
  """
  @spec set_range(:gen_statem.server_ref(), ADMX3652.Protocol.channel(), Command.range()) ::
          :ok | {:error, term()}
  def set_range(meter, channel, range) do
    command = Command.set_range(channel, range)
    :gen_statem.call(meter, command, :infinity)
  end

  @doc "Reads the configured NPLC for a channel."
  @spec get_nplc(:gen_statem.server_ref(), ADMX3652.Protocol.channel()) ::
          {:ok, float()} | {:error, term()}
  def get_nplc(meter, channel) when channel in [1, 2] do
    :gen_statem.call(meter, {:get_nplc, channel}, :infinity)
  end

  @doc "Sets the configured NPLC for a channel."
  @spec set_nplc(:gen_statem.server_ref(), ADMX3652.Protocol.channel(), number()) ::
          :ok | {:error, term()}
  def set_nplc(meter, channel, nplc) do
    command = Command.set_nplc(channel, nplc)
    :gen_statem.call(meter, command, :infinity)
  end

  @doc "Sets the power-line frequency used for NPLC values of one or greater."
  @spec set_line_frequency(:gen_statem.server_ref(), Command.line_frequency()) ::
          :ok | {:error, term()}
  def set_line_frequency(meter, frequency) do
    command = Command.set_line_frequency(frequency)
    :gen_statem.call(meter, command, :infinity)
  end

  @doc "Sets a channel to single or continuous read mode."
  @spec set_read_mode(
          :gen_statem.server_ref(),
          ADMX3652.Protocol.channel(),
          Command.read_mode()
        ) :: :ok | {:error, term()}
  def set_read_mode(meter, channel, mode) do
    command = Command.set_read_mode(channel, mode)
    :gen_statem.call(meter, command, :infinity)
  end

  @doc "Reads the shared trigger source."
  @spec get_trigger_source(:gen_statem.server_ref()) ::
          {:ok, Command.trigger_source()} | {:error, term()}
  def get_trigger_source(meter) do
    :gen_statem.call(meter, :get_trigger_source, :infinity)
  end

  @doc "Sets the shared trigger source."
  @spec set_trigger_source(:gen_statem.server_ref(), Command.trigger_source()) ::
          :ok | {:error, term()}
  def set_trigger_source(meter, source) do
    command = Command.set_trigger_source(source)
    :gen_statem.call(meter, command, :infinity)
  end

  @doc """
  Sends an arbitrary line to the instrument without verification.

  A raw command bypasses exchange tracking and invalidates the shadow state.
  It is accepted in `:starting`, `:configuring`, idle `:ready`, and
  `:desynchronised`.
  """
  @spec raw_command(:gen_statem.server_ref(), binary()) :: :ok | {:error, term()}
  def raw_command(meter, raw_line) when is_binary(raw_line) do
    :gen_statem.call(meter, {:raw_command, raw_line}, :infinity)
  end

  @doc """
  Starts the ADMX3652 process and its transport.

  Options:

    * `:transport` - transport module (required)
    * `:transport_opts` - options passed to the transport (defaults to `[]`)
    * `:pubsub` - registered name of a supervised `Phoenix.PubSub` server
      (required); lines are broadcast on `"admx3652:lines"`
    * `:configuration` - an `ADMX3652.Configuration` applied after startup
      (defaults to `ADMX3652.Configuration.default/0`)
    * `:name` - optional `:gen_statem` registration name
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts), do: StateMachine.start_link(opts)

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end
end
