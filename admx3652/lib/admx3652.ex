defmodule ADMX3652 do
  @moduledoc """
  Main process for an ADMX3652 panel meter.

  The process owns the transport and will eventually coordinate the meter's
  startup, configuration, and shadow state.
  """

  @behaviour :gen_statem

  alias ADMX3652.{Command, Exchange, Line, Shadow}

  @exchange_timeout 1_000
  @line_topic "admx3652:lines"

  @type state :: :off | :starting | :configuring | :ready | :desynchronised

  defmodule StateData do
    @moduledoc false

    @enforce_keys [:transport_mod, :transport, :pubsub]
    defstruct [:transport_mod, :transport, :pubsub, current: nil, shadow: %Shadow{}]

    @type t :: %__MODULE__{
            transport_mod: module(),
            transport: ADMX3652.Transport.t(),
            pubsub: Phoenix.PubSub.t(),
            current: nil | {:gen_statem.from(), Exchange.t()},
            shadow: Shadow.t() | :unknown
          }
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

  @doc """
  Starts the ADMX3652 process and its transport.

  Options:

    * `:transport` - transport module (required)
    * `:transport_opts` - options passed to the transport (defaults to `[]`)
    * `:pubsub` - registered name of a supervised `Phoenix.PubSub` server
      (required); lines are broadcast on `"admx3652:lines"`
    * `:name` - optional `:gen_statem` registration name
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, opts, [])
      name -> :gen_statem.start_link(server_name(name), __MODULE__, opts, [])
    end
  end

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

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(opts) do
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])
    pubsub = Keyword.fetch!(opts, :pubsub)

    {:ok, transport} = transport_mod.start_link(self(), transport_opts)

    state =
      case transport_mod.enabled?(transport) do
        {:ok, false} -> :off
        {:ok, true} -> :desynchronised
        {:error, _reason} -> :desynchronised
      end

    {:ok, state,
     %StateData{
       transport_mod: transport_mod,
       transport: transport,
       pubsub: pubsub
     }}
  end

  def off({:call, from}, _request, data), do: reply(data, from, {:error, :off})
  def off(:info, message, data), do: handle_info(message, data)
  def off(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
  def off(_event_type, _event_content, data), do: {:keep_state, data}

  def starting({:call, from}, _request, data), do: reply(data, from, {:error, :starting})
  def starting(:info, message, data), do: handle_info(message, data)
  def starting(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
  def starting(_event_type, _event_content, data), do: {:keep_state, data}

  def configuring({:call, from}, _request, data),
    do: reply(data, from, {:error, :configuring})

  def configuring(:info, message, data), do: handle_info(message, data)
  def configuring(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
  def configuring(_event_type, _event_content, data), do: {:keep_state, data}

  def ready({:call, from}, request, %StateData{current: nil} = data) do
    case command(request) do
      {:ok, command} -> start_exchange(data, from, command)
      :error -> reply(data, from, {:error, :unsupported_request})
    end
  end

  def ready({:call, from}, _request, data), do: reply(data, from, {:error, :busy})
  def ready(:info, message, data), do: handle_info(message, data)

  def ready(:internal, %Line{} = line, %StateData{current: nil} = data) do
    route_unsolicited(line, data)
  end

  def ready(
        :internal,
        %Line{} = line,
        %StateData{current: {from, exchange}} = data
      ) do
    case Exchange.offer(exchange, line.decoded) do
      {:continue, exchange, writes} ->
        publish(data, %{line | exchange_id: exchange.id})
        continue_exchange(data, from, exchange, writes)

      {:complete, result, shadow_delta} ->
        publish(data, %{line | exchange_id: exchange.id})
        finish_exchange(data, from, result, shadow_delta)

      :not_claimed ->
        route_unsolicited(line, data)

      {:invalid, reason} ->
        publish(data, line)
        fail_exchange(data, from, {:protocol, reason})
    end
  end

  def ready(
        {:timeout, :exchange},
        :expired,
        %StateData{current: {from, _exchange}} = data
      ) do
    fail_exchange(data, from, :timeout)
  end

  def ready(_event_type, _event_content, data), do: {:keep_state, data}

  def desynchronised({:call, from}, _request, data),
    do: reply(data, from, {:error, :desynchronised})

  def desynchronised(:info, message, data), do: handle_info(message, data)
  def desynchronised(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
  def desynchronised(_event_type, _event_content, data), do: {:keep_state, data}

  defp handle_info(
         {:admx3652_transport, transport, {:line, raw_line}},
         %StateData{transport: transport} = data
       ) do
    line = %Line{
      direction: :received,
      raw: raw_line,
      timestamp: System.monotonic_time(),
      decoded: ADMX3652.Protocol.decode(raw_line)
    }

    {:keep_state, data, [{:next_event, :internal, line}]}
  end

  defp handle_info(_message, data), do: {:keep_state, data}

  defp command({:get_range, channel}) when channel in [1, 2] do
    {:ok, Command.get_range(channel)}
  end

  defp command({:set_range, channel, range}) do
    {:ok, Command.set_range(channel, range)}
  end

  defp command(_request), do: :error

  defp start_exchange(data, from, command) do
    exchange_id = make_ref()
    {exchange, writes} = Exchange.start(exchange_id, command)

    case write_all(data, exchange.id, writes) do
      :ok ->
        data = %{data | current: {from, exchange}}

        {:keep_state, data, [{{:timeout, :exchange}, @exchange_timeout, :expired}]}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp continue_exchange(data, from, exchange, writes) do
    case write_all(data, exchange.id, writes) do
      :ok ->
        {:keep_state, %{data | current: {from, exchange}}}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp finish_exchange(data, from, result, shadow_delta) do
    shadow = Shadow.apply(data.shadow, shadow_delta)
    data = %{data | current: nil, shadow: shadow}

    {:keep_state, data, [{{:timeout, :exchange}, :cancel}, {:reply, from, result}]}
  end

  defp fail_exchange(data, from, reason) do
    data = %{data | current: nil, shadow: :unknown}

    {:next_state, :desynchronised, data,
     [{{:timeout, :exchange}, :cancel}, {:reply, from, {:error, reason}}]}
  end

  defp write_all(data, exchange_id, writes) do
    Enum.reduce_while(writes, :ok, fn write, :ok ->
      case data.transport_mod.write(data.transport, write) do
        :ok ->
          raw_line = IO.iodata_to_binary(write)

          publish(data, %Line{
            direction: :sent,
            raw: raw_line,
            timestamp: System.monotonic_time(),
            decoded: nil,
            exchange_id: exchange_id
          })

          {:cont, :ok}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  # Not implemented yet: unexpected-message policy.
  defp route_unsolicited(line, data) do
    publish(data, line)
    {:keep_state, data}
  end

  defp publish(%StateData{pubsub: pubsub}, line) do
    :ok = Phoenix.PubSub.broadcast(pubsub, @line_topic, line)
  end

  defp reply(data, from, response) do
    {:keep_state, data, [{:reply, from, response}]}
  end

  defp server_name(name) when is_atom(name), do: {:local, name}
  defp server_name({:global, _term} = name), do: name
  defp server_name({:via, _module, _term} = name), do: name
end
