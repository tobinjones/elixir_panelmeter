defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.{Line, Shadow, StateMachine, TestTransport}
  alias ADMX3652.StateMachine.Data

  @line_topic "admx3652:lines"

  test "starts in :off and starts its transport" do
    pubsub = start_pubsub()

    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self()],
               pubsub: pubsub
             )

    assert {:off,
            %Data{
              transport_mod: TestTransport,
              transport: transport
            }} = :sys.get_state(meter)

    assert Process.alive?(transport)
  end

  test "can be registered by name" do
    name = :admx3652_test_meter
    pubsub = start_pubsub()

    assert {:ok, meter} =
             ADMX3652.start_link(
               name: name,
               transport: TestTransport,
               transport_opts: [test: self()],
               pubsub: pubsub
             )

    assert Process.whereis(name) == meter
  end

  test "starts in :desynchronised when the transport is already enabled" do
    pubsub = start_pubsub()

    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self(), enabled: true],
               pubsub: pubsub
             )

    assert {:desynchronised, %Data{shadow: :unknown}} =
             :sys.get_state(meter)
  end

  test "rejects commands while off" do
    {:ok, meter} = start_meter()

    assert ADMX3652.get_range(meter, 1) == {:error, :off}
    assert ADMX3652.raw_command(meter, "*IDN?") == {:error, :off}
  end

  test "ready banner advances startup to configuring" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_meter(pubsub: pubsub)

    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}

    assert {:starting, %Data{transport: transport, shadow: :unknown}} =
             :sys.get_state(meter)

    TestTransport.send_line(transport, "ADC self check done")

    assert_receive %Line{
      direction: :received,
      decoded: {:device_message, :adc_self_check_done},
      exchange_id: nil
    }

    assert {:starting, %Data{}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_receive %Line{
      direction: :received,
      decoded: {:device_message, :ready},
      exchange_id: nil
    }

    assert {:configuring, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)

    assert ADMX3652.raw_command(meter, "SYSTem:VERSion?") == :ok
    assert_receive {:transport_write, "SYSTem:VERSion?"}
    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)

    assert ADMX3652.raw_command(meter, "*IDN?") == :ok
    assert_receive {:transport_write, "*IDN?"}
    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)

    assert ADMX3652.disable(meter) == :ok
    assert_receive {:transport_enabled, false}
    assert {:off, %Data{current: nil, shadow: %Shadow{}}} = :sys.get_state(meter)
  end

  test "startup timeout desynchronises the meter" do
    {:ok, meter} = start_meter()

    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    assert {:starting, data} = :sys.get_state(meter)

    assert {:next_state, :desynchronised, %Data{current: nil, shadow: :unknown}} =
             StateMachine.starting(:state_timeout, :expired, data)
  end

  test "a ready banner while off remains unsolicited" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_meter(pubsub: pubsub)
    {:off, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_receive %Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    }

    assert {:off, %Data{}} = :sys.get_state(meter)
  end

  test "a second ready banner while configuring desynchronises the meter" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_meter(pubsub: pubsub)
    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_receive %Line{decoded: {:device_message, :ready}}
    assert {:configuring, %Data{}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_receive %Line{decoded: {:device_message, :ready}}
    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
  end

  test "a ready banner while ready indicates an unexpected restart" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)
    {:ready, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_receive %Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    }

    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
  end

  test "an unexpected restart interrupts an active exchange" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_receive %Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    }

    assert Task.await(task) == {:error, :device_restarted}
    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
  end

  test "publishes received lines even when no exchange is active" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_meter(pubsub: pubsub)

    {:off, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Channel1: -0.0000006 ")

    assert_receive %Line{
      direction: :received,
      raw: "Channel1: -0.0000006 ",
      timestamp: timestamp,
      decoded: {:measurement, 1, value},
      exchange_id: nil
    }

    assert is_integer(timestamp)
    assert value == -0.0000006
  end

  test "a raw command from ready is published without an exchange id and desynchronises" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)

    assert ADMX3652.raw_command(meter, "SYSTem:VERSion?") == :ok

    assert_receive {:transport_write, "SYSTem:VERSion?"}

    assert_receive %Line{
      direction: :sent,
      raw: "SYSTem:VERSion?",
      decoded: nil,
      exchange_id: nil
    }

    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} =
             :sys.get_state(meter)
  end

  test "raw commands remain available while desynchronised" do
    {:ok, meter} =
      start_meter(transport_opts: [test: self(), enabled: true])

    assert ADMX3652.raw_command(meter, "*IDN?") == :ok
    assert_receive {:transport_write, "*IDN?"}

    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)
    assert ADMX3652.get_range(meter, 1) == {:error, :desynchronised}
  end

  test "gets a range through a verified exchange" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, 2.0}
    assert {:ready, %Data{current: nil, shadow: %Shadow{}}} = :sys.get_state(meter)
  end

  test "publishes sent and claimed lines with one exchange id" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_receive %Line{
      direction: :sent,
      raw: "CONFigure:VOLTage:DC? 1",
      decoded: nil,
      exchange_id: exchange_id
    }

    assert is_reference(exchange_id)

    assert_receive %Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      decoded: nil,
      exchange_id: ^exchange_id
    }

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_receive %Line{
      direction: :received,
      raw: "CHAN[1]-RANGE: 2.000000",
      decoded: {:range, 1, 2.0},
      exchange_id: ^exchange_id
    }

    assert_receive %Line{
      direction: :received,
      raw: ~s(0,"No error"),
      decoded: {:error_queue, 0, "No error"},
      exchange_id: ^exchange_id
    }

    assert Task.await(task) == {:ok, 2.0}
  end

  test "does not label a received line rejected as invalid by the exchange" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_receive %Line{direction: :sent}
    assert_receive %Line{direction: :sent}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")

    assert_receive %Line{direction: :received, exchange_id: exchange_id}

    assert is_reference(exchange_id)

    TestTransport.send_line(transport, "CHAN[1]-RANGE: 3.000000")

    assert_receive %Line{
      direction: :received,
      raw: "CHAN[1]-RANGE: 3.000000",
      exchange_id: nil
    }

    assert Task.await(task) ==
             {:error, {:protocol, {:command_response, :duplicate_range_response}}}

    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)
  end

  test "interleaves follow-up writes into the published line stream" do
    pubsub = start_line_pubsub()
    {:ok, meter} = start_ready_meter(pubsub: pubsub)

    task = Task.async(fn -> ADMX3652.set_range(meter, 1, 2.0) end)

    assert_receive %Line{
      direction: :sent,
      raw: "CONFigure:VOLTage:DC 1,2.0",
      exchange_id: exchange_id
    }

    assert_receive %Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      exchange_id: ^exchange_id
    }

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(-224,"Illegal parameter value"))

    assert_receive %Line{
      direction: :received,
      decoded: {:error_queue, -224, "Illegal parameter value"},
      exchange_id: ^exchange_id
    }

    assert_receive %Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      exchange_id: ^exchange_id
    }

    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_receive %Line{
      direction: :received,
      decoded: {:error_queue, 0, "No error"},
      exchange_id: ^exchange_id
    }

    assert Task.await(task) ==
             {:error, {:device, [{-224, "Illegal parameter value"}]}}
  end

  test "commits a set range to shadow only after verification" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.set_range(meter, 2, :auto) end)

    assert_receive {:transport_write, "CONFigure:VOLTage:DC 2,auto"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport, shadow: shadow}} = :sys.get_state(meter)
    assert shadow.configured_range[2] == :unknown

    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == :ok

    assert {:ready, %Data{shadow: shadow}} = :sys.get_state(meter)
    assert shadow.configured_range[2] == :auto
  end

  test "rejects a second command while an exchange is active" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert ADMX3652.get_range(meter, 2) == {:error, :busy}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, 2.0}
  end

  test "rejects a raw command while an exchange is active" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert ADMX3652.raw_command(meter, "*IDN?") == {:error, :busy}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, 2.0}
  end

  test "disable interrupts an active exchange" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert ADMX3652.disable(meter) == :ok
    assert_receive {:transport_enabled, false}

    assert Task.await(task) == {:error, :disabled}

    assert {:off, %Data{current: nil, shadow: %Shadow{}}} = :sys.get_state(meter)
  end

  test "does not commit a rejected setting" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.set_range(meter, 1, 2.0) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC 1,2.0"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(-224,"Illegal parameter value"))
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) ==
             {:error, {:device, [{-224, "Illegal parameter value"}]}}

    assert {:ready, %Data{shadow: %Shadow{configured_range: configured_range}}} =
             :sys.get_state(meter)

    assert configured_range[1] == :unknown
  end

  defp start_meter(opts \\ []) do
    pubsub = Keyword.get_lazy(opts, :pubsub, &start_pubsub/0)

    defaults = [
      transport: TestTransport,
      transport_opts: [test: self()],
      pubsub: pubsub
    ]

    ADMX3652.start_link(Keyword.merge(defaults, opts))
  end

  defp start_ready_meter(opts \\ []) do
    with {:ok, meter} <- start_meter(opts) do
      :sys.replace_state(meter, fn {_state, data} -> {:ready, data} end)
      {:ok, meter}
    end
  end

  defp start_line_pubsub do
    pubsub = start_pubsub()
    :ok = Phoenix.PubSub.subscribe(pubsub, @line_topic)
    pubsub
  end

  defp start_pubsub do
    name = Module.concat(__MODULE__, "PubSub#{System.unique_integer([:positive])}")
    start_supervised!({Phoenix.PubSub, name: name})
    name
  end
end
