defmodule ADMX3652.StateMachine do
  @moduledoc false

  @behaviour :gen_statem

  alias ADMX3652.{Command, Exchange, ExpectedReading, Line, Protocol, Reading, Shadow}

  @exchange_timeout 1_000
  @line_topic "admx3652:lines"
  @reading_topic "admx3652:readings"

  @type state :: :off | :starting | :configuring | :ready | :desynchronised

  defmodule Data do
    @moduledoc false

    @enforce_keys [:transport_mod, :transport, :pubsub]
    defstruct [
      :transport_mod,
      :transport,
      :pubsub,
      current: nil,
      expected: %{},
      shadow: %Shadow{}
    ]

    @type t :: %__MODULE__{
            transport_mod: module(),
            transport: ADMX3652.Transport.t(),
            pubsub: Phoenix.PubSub.t(),
            current: nil | {:gen_statem.from(), Exchange.t()},
            expected: %{optional(ADMX3652.Protocol.channel()) => ExpectedReading.t()},
            shadow: Shadow.t() | :unknown
          }
  end

  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, opts, [])
      name -> :gen_statem.start_link(server_name(name), __MODULE__, opts, [])
    end
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(opts) do
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])
    pubsub = Keyword.fetch!(opts, :pubsub)

    {:ok, transport} = transport_mod.start_link(self(), transport_opts)

    {state, shadow} =
      case transport_mod.enabled?(transport) do
        {:ok, false} -> {:off, %Shadow{}}
        {:ok, true} -> {:desynchronised, :unknown}
        {:error, _reason} -> {:desynchronised, :unknown}
      end

    {:ok, state,
     %Data{
       transport_mod: transport_mod,
       transport: transport,
       pubsub: pubsub,
       shadow: shadow
     }}
  end

  def off({:call, from}, :enable, data), do: enable_instrument(data, from)
  def off({:call, from}, :disable, data), do: reply(data, from, :ok)
  def off({:call, from}, _request, data), do: reply(data, from, {:error, :off})
  def off(:info, message, data), do: handle_info(message, data)
  def off(:internal, %Line{} = line, data), do: process_line(line, data)
  def off(_event_type, _event_content, data), do: {:keep_state, data}

  def starting({:call, from}, :enable, data), do: reply(data, from, :ok)
  def starting({:call, from}, :disable, data), do: disable_instrument(data, from)

  def starting({:call, from}, {:raw_command, raw_line}, data) do
    send_raw_command(data, from, raw_line)
  end

  def starting({:call, from}, _request, data), do: reply(data, from, {:error, :starting})
  def starting(:info, message, data), do: handle_info(message, data)
  def starting(:internal, %Line{} = line, data), do: process_line(line, data)
  def starting(_event_type, _event_content, data), do: {:keep_state, data}

  def configuring({:call, from}, :enable, data), do: reply(data, from, :ok)
  def configuring({:call, from}, :disable, data), do: disable_instrument(data, from)

  def configuring({:call, from}, {:raw_command, raw_line}, data) do
    send_raw_command(data, from, raw_line)
  end

  def configuring({:call, from}, _request, data),
    do: reply(data, from, {:error, :configuring})

  def configuring(:info, message, data), do: handle_info(message, data)
  def configuring(:internal, %Line{} = line, data), do: process_line(line, data)
  def configuring(_event_type, _event_content, data), do: {:keep_state, data}

  def ready({:call, from}, :enable, data), do: reply(data, from, :ok)

  def ready({:call, from}, :disable, data) do
    disable_instrument(data, from)
  end

  def ready(
        {:call, from},
        {:raw_command, raw_line},
        %Data{current: nil} = data
      ) do
    send_raw_command(data, from, raw_line)
  end

  def ready({:call, from}, request, %Data{current: nil} = data) do
    case command(request) do
      {:ok, command} -> start_exchange(data, from, command)
      :error -> reply(data, from, {:error, :unsupported_request})
    end
  end

  def ready({:call, from}, _request, data), do: reply(data, from, {:error, :busy})
  def ready(:info, message, data), do: handle_info(message, data)

  def ready(:internal, %Line{} = line, data), do: process_line(line, data)

  def ready(
        {:timeout, :exchange},
        :expired,
        %Data{current: {from, _exchange}} = data
      ) do
    fail_exchange(data, from, :timeout)
  end

  def ready(_event_type, _event_content, data), do: {:keep_state, data}

  def desynchronised({:call, from}, :enable, data), do: reply(data, from, :ok)

  def desynchronised({:call, from}, :disable, data) do
    disable_instrument(data, from)
  end

  def desynchronised({:call, from}, {:raw_command, raw_line}, data) do
    send_raw_command(data, from, raw_line)
  end

  def desynchronised({:call, from}, _request, data),
    do: reply(data, from, {:error, :desynchronised})

  def desynchronised(:info, message, data), do: handle_info(message, data)
  def desynchronised(:internal, %Line{} = line, data), do: process_line(line, data)
  def desynchronised(_event_type, _event_content, data), do: {:keep_state, data}

  defp handle_info(
         {:admx3652_transport, transport, {:line, raw_line}},
         %Data{transport: transport} = data
       ) do
    line = %Line{
      direction: :received,
      raw: raw_line,
      timestamp: System.monotonic_time(),
      decoded: Protocol.decode(raw_line)
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

  defp command({:measure, channel}) when channel in [1, 2] do
    {:ok, Command.measure(channel)}
  end

  defp command(_request), do: :error

  defp start_exchange(data, from, command) do
    exchange_id = make_ref()
    {exchange, writes} = Exchange.start(exchange_id, command)

    case write_all(data, exchange.id, writes) do
      {:ok, sent_lines} ->
        data =
          data
          |> expect_reading(exchange, sent_lines)
          |> Map.put(:current, {from, exchange})

        {:keep_state, data, [{{:timeout, :exchange}, @exchange_timeout, :expired}]}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp continue_exchange(data, from, exchange, writes) do
    case write_all(data, exchange.id, writes) do
      {:ok, _sent_lines} ->
        {:keep_state, %{data | current: {from, exchange}}}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp finish_exchange(data, from, exchange, result, shadow_delta) do
    shadow = Shadow.apply(data.shadow, shadow_delta)
    data = %{data | current: nil, shadow: shadow}

    data =
      if match?({:error, _reason}, result), do: discard_expected(data, exchange.id), else: data

    {:keep_state, data, [{{:timeout, :exchange}, :cancel}, {:reply, from, result}]}
  end

  defp fail_exchange(data, from, reason) do
    data = %{data | current: nil, expected: %{}, shadow: :unknown}

    {:next_state, :desynchronised, data,
     [{{:timeout, :exchange}, :cancel}, {:reply, from, {:error, reason}}]}
  end

  defp enable_instrument(data, from) do
    case data.transport_mod.set_enabled(data.transport, true) do
      :ok ->
        data = %{data | expected: %{}, shadow: :unknown}
        {:next_state, :starting, data, [{:reply, from, :ok}]}

      {:error, reason} ->
        data = %{data | expected: %{}, shadow: :unknown}

        {:next_state, :desynchronised, data, [{:reply, from, {:error, {:transport, reason}}}]}
    end
  end

  defp disable_instrument(data, from) do
    exchange_actions = interrupt_exchange(data.current)

    case data.transport_mod.set_enabled(data.transport, false) do
      :ok ->
        data = %{data | current: nil, expected: %{}, shadow: %Shadow{}}
        {:next_state, :off, data, exchange_actions ++ [{:reply, from, :ok}]}

      {:error, reason} ->
        data = %{data | current: nil, expected: %{}, shadow: :unknown}

        {:next_state, :desynchronised, data,
         exchange_actions ++ [{:reply, from, {:error, {:transport, reason}}}]}
    end
  end

  defp interrupt_exchange(nil), do: []

  defp interrupt_exchange({exchange_from, _exchange}) do
    [
      {{:timeout, :exchange}, :cancel},
      {:reply, exchange_from, {:error, :disabled}}
    ]
  end

  defp send_raw_command(data, from, raw_line) do
    data = %{data | expected: %{}, shadow: :unknown}

    response =
      case write_all(data, nil, [raw_line]) do
        {:ok, _sent_lines} -> :ok
        {:error, reason} -> {:error, {:transport, reason}}
      end

    {:next_state, :desynchronised, data, [{:reply, from, response}]}
  end

  defp write_all(data, exchange_id, writes) do
    Enum.reduce_while(writes, {:ok, []}, fn write, {:ok, sent_lines} ->
      case data.transport_mod.write(data.transport, write) do
        :ok ->
          raw_line = IO.iodata_to_binary(write)

          line = %Line{
            direction: :sent,
            raw: raw_line,
            timestamp: System.monotonic_time(),
            decoded: nil,
            exchange_id: exchange_id
          }

          publish_line(data, line)

          {:cont, {:ok, [line | sent_lines]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp process_line(line, data) do
    {line, exchange_effect} = offer_line(line, data.current)
    data = publish_reading(line, data)
    publish_line(data, line)
    apply_exchange_effect(exchange_effect, data)
  end

  defp offer_line(line, nil), do: {line, :none}

  defp offer_line(line, {from, exchange}) do
    case Exchange.offer(exchange, line.decoded) do
      {:continue, exchange, writes} ->
        {%{line | exchange_id: exchange.id}, {:continue, from, exchange, writes}}

      {:complete, result, shadow_delta} ->
        {%{line | exchange_id: exchange.id}, {:complete, from, exchange, result, shadow_delta}}

      :not_claimed ->
        {line, :none}

      {:invalid, reason} ->
        {line, {:invalid, from, reason}}
    end
  end

  defp apply_exchange_effect(:none, data), do: {:keep_state, data}

  defp apply_exchange_effect({:continue, from, exchange, writes}, data) do
    continue_exchange(data, from, exchange, writes)
  end

  defp apply_exchange_effect({:complete, from, exchange, result, shadow_delta}, data) do
    finish_exchange(data, from, exchange, result, shadow_delta)
  end

  defp apply_exchange_effect({:invalid, from, reason}, data) do
    fail_exchange(data, from, {:protocol, reason})
  end

  defp expect_reading(data, %Exchange{command: {:measure, channel}} = exchange, sent_lines) do
    [%Line{timestamp: sent_at} | _rest] = Enum.reverse(sent_lines)
    expected = ExpectedReading.new(channel, exchange.id, sent_at, data.shadow)
    %{data | expected: Map.put(data.expected, channel, expected)}
  end

  defp expect_reading(data, _exchange, _sent_lines), do: data

  defp publish_reading(%Line{decoded: {:measurement, channel, value}} = line, data) do
    publish_reading(data, line, channel, value)
  end

  defp publish_reading(%Line{decoded: {:overload, channel}} = line, data) do
    publish_reading(data, line, channel, :overload)
  end

  defp publish_reading(_line, data), do: data

  defp publish_reading(data, line, channel, value) do
    {expected, expected_readings} = Map.pop(data.expected, channel)

    reading = %Reading{
      channel: channel,
      value: value,
      timestamp: line.timestamp,
      exchange_id: expected && expected.exchange_id,
      requested_at: expected && expected.sent_at,
      expected_at: expected && expected.expected_at
    }

    :ok = Phoenix.PubSub.broadcast(data.pubsub, @reading_topic, reading)
    %{data | expected: expected_readings}
  end

  defp discard_expected(data, exchange_id) do
    expected =
      Map.reject(data.expected, fn {_channel, expected} ->
        expected.exchange_id == exchange_id
      end)

    %{data | expected: expected}
  end

  defp publish_line(%Data{pubsub: pubsub}, line) do
    :ok = Phoenix.PubSub.broadcast(pubsub, @line_topic, line)
  end

  defp reply(data, from, response) do
    {:keep_state, data, [{:reply, from, response}]}
  end

  defp server_name(name) when is_atom(name), do: {:local, name}
  defp server_name({:global, _term} = name), do: name
  defp server_name({:via, _module, _term} = name), do: name
end
