defmodule ADMX3652.StateMachine do
  @moduledoc false

  @behaviour :gen_statem

  alias ADMX3652.{
    Command,
    Configuration,
    Exchange,
    ExpectedReading,
    Line,
    Protocol,
    Reading,
    Shadow
  }

  @exchange_timeout 1_000
  @startup_timeout 10_000

  @type state :: :off | :starting | :configuring | :ready | :desynchronised

  defmodule Data do
    @moduledoc false

    @enforce_keys [:transport_mod, :transport, :event_target]
    defstruct [
      :transport_mod,
      :transport,
      :event_target,
      :configuration,
      current: nil,
      pending: [],
      expected: %{},
      shadow: %Shadow{}
    ]

    @type t :: %__MODULE__{
            transport_mod: module(),
            transport: ADMX3652.Transport.t(),
            event_target: ADMX3652.event_target(),
            configuration: Configuration.t(),
            current:
              nil
              | {:configuring, Exchange.t()}
              | {:gen_statem.from(), Exchange.t(), ExpectedReading.t() | nil},
            pending: [Command.t()],
            expected: %{optional(ADMX3652.Protocol.channel()) => ExpectedReading.t()},
            shadow: Shadow.t() | :unknown
          }
  end

  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) do
    configuration = Keyword.get(opts, :configuration, Configuration.default())

    case Configuration.validate(configuration) do
      :ok ->
        opts = Keyword.put(opts, :configuration, configuration)

        case Keyword.get(opts, :name) do
          nil -> :gen_statem.start_link(__MODULE__, opts, [])
          name -> :gen_statem.start_link(server_name(name), __MODULE__, opts, [])
        end

      {:error, reason} ->
        {:error, {:invalid_configuration, reason}}
    end
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init(opts) do
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])
    event_target = Keyword.fetch!(opts, :event_target)
    configuration = Keyword.fetch!(opts, :configuration)

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
       event_target: event_target,
       configuration: configuration,
       shadow: shadow
     }}
  end

  def off({:call, from}, :enable, data), do: enable_instrument(data, from)
  def off({:call, from}, :disable, data), do: reply(data, from, :ok)
  def off({:call, from}, _request, data), do: reply(data, from, {:error, :off})
  def off(:info, message, data), do: handle_info(message, data)
  def off(_event_type, _event_content, data), do: {:keep_state, data}

  def starting({:call, from}, :enable, data), do: reply(data, from, :ok)
  def starting({:call, from}, :disable, data), do: disable_instrument(data, from)

  def starting({:call, from}, {:raw_command, raw_line}, data) do
    send_raw_command(data, from, raw_line)
  end

  def starting({:call, from}, _request, data), do: reply(data, from, {:error, :starting})
  def starting(:info, message, data), do: handle_info(message, data)

  def starting(:internal, %Line{decoded: {:device_message, :ready}} = line, data) do
    publish(data, line)

    data = %{
      data
      | current: nil,
        pending: Configuration.commands(data.configuration),
        shadow: %Shadow{}
    }

    {:next_state, :configuring, data, [{:next_event, :internal, :configure_next}]}
  end

  def starting(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
  def starting(:state_timeout, :expired, data), do: desynchronise(data)
  def starting(_event_type, _event_content, data), do: {:keep_state, data}

  def configuring({:call, from}, :enable, data), do: reply(data, from, :ok)
  def configuring({:call, from}, :disable, data), do: disable_instrument(data, from)

  def configuring({:call, from}, {:raw_command, raw_line}, data) do
    send_raw_command(data, from, raw_line)
  end

  def configuring({:call, from}, _request, data),
    do: reply(data, from, {:error, :configuring})

  def configuring(:info, message, data), do: handle_info(message, data)

  def configuring(:internal, :configure_next, %Data{current: nil, pending: []} = data) do
    if Shadow.complete?(data.shadow) and compatible_read_modes?(data.shadow) do
      {:next_state, :ready, data}
    else
      desynchronise(data)
    end
  end

  def configuring(
        :internal,
        :configure_next,
        %Data{current: nil, pending: [command | pending]} = data
      ) do
    start_exchange(%{data | pending: pending}, :configuring, command)
  end

  def configuring(:internal, %Line{decoded: {:device_message, :ready}} = line, data) do
    unexpected_restart(line, data)
  end

  def configuring(:internal, %Line{} = line, %Data{current: nil} = data),
    do: route_unsolicited(line, data)

  def configuring(
        :internal,
        %Line{} = line,
        %Data{current: {:configuring, exchange}} = data
      ) do
    case Exchange.offer(exchange, line.decoded) do
      {:continue, exchange, writes} ->
        publish(data, %{line | exchange_id: exchange.id})
        continue_exchange(data, :configuring, exchange, writes)

      {:complete, result, shadow_delta} ->
        publish(data, %{line | exchange_id: exchange.id})
        finish_configuration_exchange(data, result, shadow_delta)

      :not_claimed ->
        route_unsolicited(line, data)

      {:invalid, reason} ->
        publish(data, line)
        fail_exchange(data, :configuring, {:protocol, reason})
    end
  end

  def configuring(
        {:timeout, :exchange},
        :expired,
        %Data{current: {:configuring, _exchange}} = data
      ) do
    fail_exchange(data, :configuring, :timeout)
  end

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

  def ready(:internal, %Line{decoded: {:device_message, :ready}} = line, data) do
    unexpected_restart(line, data)
  end

  def ready(:internal, %Line{} = line, %Data{current: nil} = data) do
    route_unsolicited(line, data)
  end

  def ready(
        :internal,
        %Line{} = line,
        %Data{current: {from, exchange, expected}} = data
      ) do
    case Exchange.offer(exchange, line.decoded) do
      {:continue, exchange, writes} ->
        publish(data, %{line | exchange_id: exchange.id})
        continue_exchange(data, from, exchange, expected, writes)

      {:complete, result, shadow_delta} ->
        publish(data, %{line | exchange_id: exchange.id})
        finish_exchange(data, from, exchange, expected, result, shadow_delta)

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
        %Data{current: {from, _exchange, _expected}} = data
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

  def desynchronised(:internal, %Line{decoded: {:device_message, :ready}} = line, data) do
    unexpected_restart(line, data)
  end

  def desynchronised(:internal, %Line{} = line, data), do: route_unsolicited(line, data)
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

  defp command({:get_nplc, channel}) when channel in [1, 2] do
    {:ok, Command.get_nplc(channel)}
  end

  defp command({:set_nplc, channel, nplc}) do
    {:ok, Command.set_nplc(channel, nplc)}
  end

  defp command({:set_line_frequency, frequency}) do
    {:ok, Command.set_line_frequency(frequency)}
  end

  defp command({:set_read_mode, channel, mode}) do
    {:ok, Command.set_read_mode(channel, mode)}
  end

  defp command(:get_trigger_source), do: {:ok, Command.get_trigger_source()}

  defp command({:set_trigger_source, source}) do
    {:ok, Command.set_trigger_source(source)}
  end

  defp command({:measure, channel}) when channel in [1, 2] do
    {:ok, Command.measure(channel)}
  end

  defp command(_request), do: :error

  defp start_exchange(data, :configuring, command) do
    exchange_id = make_ref()
    {exchange, writes} = Exchange.start(exchange_id, command)

    case write_all(data, exchange.id, writes) do
      {:ok, _sent_lines} ->
        {:keep_state, %{data | current: {:configuring, exchange}},
         [{{:timeout, :exchange}, @exchange_timeout, :expired}]}

      {:error, reason} ->
        fail_exchange(data, :configuring, {:transport, reason})
    end
  end

  defp start_exchange(data, from, command) do
    exchange_id = make_ref()
    {exchange, writes} = Exchange.start(exchange_id, command)

    case write_all(data, exchange.id, writes) do
      {:ok, sent_lines} ->
        {data, expected} = expect_reading(data, exchange, sent_lines)
        data = %{data | current: {from, exchange, expected}}

        {:keep_state, data, [{{:timeout, :exchange}, @exchange_timeout, :expired}]}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp continue_exchange(data, :configuring, exchange, writes) do
    case write_all(data, exchange.id, writes) do
      {:ok, _sent_lines} ->
        {:keep_state, %{data | current: {:configuring, exchange}}}

      {:error, reason} ->
        fail_exchange(data, :configuring, {:transport, reason})
    end
  end

  defp continue_exchange(data, from, exchange, expected, writes) do
    case write_all(data, exchange.id, writes) do
      {:ok, _sent_lines} ->
        {:keep_state, %{data | current: {from, exchange, expected}}}

      {:error, reason} ->
        fail_exchange(data, from, {:transport, reason})
    end
  end

  defp finish_exchange(data, from, exchange, expected, result, shadow_delta) do
    shadow = Shadow.apply(data.shadow, shadow_delta)
    data = %{data | current: nil, shadow: shadow}

    data =
      if match?({:error, _reason}, result), do: discard_expected(data, exchange.id), else: data

    result =
      case {expected, result} do
        {%ExpectedReading{}, :ok} -> {:ok, expected}
        _other -> result
      end

    {:keep_state, data, [{{:timeout, :exchange}, :cancel}, {:reply, from, result}]}
  end

  defp finish_configuration_exchange(data, {:error, reason}, _shadow_delta) do
    fail_exchange(data, :configuring, {:device, reason})
  end

  defp finish_configuration_exchange(data, _result, shadow_delta) do
    shadow = Shadow.apply(data.shadow, shadow_delta)
    data = %{data | current: nil, shadow: shadow}

    {:keep_state, data,
     [{{:timeout, :exchange}, :cancel}, {:next_event, :internal, :configure_next}]}
  end

  defp fail_exchange(data, :configuring, _reason) do
    data = %{data | current: nil, pending: [], expected: %{}, shadow: :unknown}

    {:next_state, :desynchronised, data, [{{:timeout, :exchange}, :cancel}]}
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

        {:next_state, :starting, data,
         [{:state_timeout, @startup_timeout, :expired}, {:reply, from, :ok}]}

      {:error, reason} ->
        data = %{data | expected: %{}, shadow: :unknown}

        {:next_state, :desynchronised, data, [{:reply, from, {:error, {:transport, reason}}}]}
    end
  end

  defp disable_instrument(data, from) do
    exchange_actions = interrupt_exchange(data.current, :disabled)

    case data.transport_mod.set_enabled(data.transport, false) do
      :ok ->
        data = %{data | current: nil, pending: [], expected: %{}, shadow: %Shadow{}}
        {:next_state, :off, data, exchange_actions ++ [{:reply, from, :ok}]}

      {:error, reason} ->
        data = %{data | current: nil, pending: [], expected: %{}, shadow: :unknown}

        {:next_state, :desynchronised, data,
         exchange_actions ++ [{:reply, from, {:error, {:transport, reason}}}]}
    end
  end

  defp interrupt_exchange(nil, _reason), do: []

  defp interrupt_exchange({:configuring, _exchange}, _reason) do
    [{{:timeout, :exchange}, :cancel}]
  end

  defp interrupt_exchange({exchange_from, _exchange, _expected}, reason) do
    [
      {{:timeout, :exchange}, :cancel},
      {:reply, exchange_from, {:error, reason}}
    ]
  end

  defp unexpected_restart(line, data) do
    publish(data, line)
    exchange_actions = interrupt_exchange(data.current, :device_restarted)
    data = %{data | current: nil, pending: [], expected: %{}, shadow: :unknown}

    {:next_state, :desynchronised, data, exchange_actions}
  end

  defp desynchronise(data) do
    data = %{data | current: nil, pending: [], expected: %{}, shadow: :unknown}
    {:next_state, :desynchronised, data}
  end

  defp send_raw_command(data, from, raw_line) do
    data = %{data | current: nil, pending: [], expected: %{}, shadow: :unknown}

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

          emit(data, {:line, line})

          {:cont, {:ok, [line | sent_lines]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp route_unsolicited(line, data) do
    data = emit_reading(line, data)
    publish(data, line)
    {:keep_state, data}
  end

  defp expect_reading(
         data,
         %Exchange{command: {:measure, channel}} = exchange,
         sent_lines
       ) do
    [%Line{timestamp: sent_at} | _rest] = Enum.reverse(sent_lines)
    expected = ExpectedReading.new(channel, exchange.id, sent_at, data.shadow)
    data = %{data | expected: Map.put(data.expected, channel, expected)}

    {data, expected}
  end

  defp expect_reading(data, _exchange, _sent_lines), do: {data, nil}

  defp emit_reading(%Line{decoded: {:measurement, channel, value}} = line, data) do
    emit_reading(data, line, channel, value)
  end

  defp emit_reading(%Line{decoded: {:overload, channel}} = line, data) do
    emit_reading(data, line, channel, :overload)
  end

  defp emit_reading(_line, data), do: data

  defp emit_reading(data, line, channel, value) do
    {expected, expected_readings} = Map.pop(data.expected, channel)

    reading = %Reading{
      channel: channel,
      value: value,
      timestamp: line.timestamp,
      expected: expected
    }

    emit(data, {:reading, reading})
    %{data | expected: expected_readings}
  end

  defp discard_expected(data, exchange_id) do
    expected =
      Map.reject(data.expected, fn {_channel, expected} ->
        expected.exchange_id == exchange_id
      end)

    %{data | expected: expected}
  end

  defp emit(%Data{event_target: event_target}, event) do
    send(event_target, {:admx3652, self(), event})
    :ok
  end

  defp publish(data, line), do: emit(data, {:line, line})

  defp reply(data, from, response) do
    {:keep_state, data, [{:reply, from, response}]}
  end

  defp compatible_read_modes?(%Shadow{
         trigger_source: :external,
         read_mode: %{1 => mode_1, 2 => mode_2}
       }),
       do: mode_1 == mode_2

  defp compatible_read_modes?(_shadow), do: true

  defp server_name(name) when is_atom(name), do: {:local, name}
  defp server_name({:global, _term} = name), do: name
  defp server_name({:via, _module, _term} = name), do: name
end
