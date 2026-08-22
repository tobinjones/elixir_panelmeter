defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.{ExpectedReading, Line, Reading, Shadow, TestTransport}
  alias ADMX3652.StateMachine.Data

  defmacrop assert_line(pattern) do
    quote do
      assert_receive {:admx3652, _meter, {:line, unquote(pattern)}}
    end
  end

  defmacrop assert_reading(pattern) do
    quote do
      assert_receive {:admx3652, _meter, {:reading, unquote(pattern)}}
    end
  end

  test "starts in :off and starts its transport" do
    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self()],
               event_target: self()
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

    assert {:ok, meter} =
             ADMX3652.start_link(
               name: name,
               transport: TestTransport,
               transport_opts: [test: self()],
               event_target: self()
             )

    assert Process.whereis(name) == meter
  end

  test "starts in :desynchronised when the transport is already enabled" do
    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self(), enabled: true],
               event_target: self()
             )

    assert {:desynchronised, %Data{shadow: :unknown}} =
             :sys.get_state(meter)
  end

  test "rejects commands while off" do
    {:ok, meter} = start_meter()

    assert ADMX3652.get_range(meter, 1) == {:error, :off}
    assert ADMX3652.raw_command(meter, "*IDN?") == {:error, :off}
  end

  test "enable, raw commands, and disable follow the temporary lifecycle" do
    {:ok, meter} = start_meter()

    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}

    assert {:starting, %Data{transport: transport, shadow: :unknown}} =
             :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_line(%Line{
      direction: :received,
      decoded: {:device_message, :ready},
      exchange_id: nil
    })

    assert {:starting, %Data{}} = :sys.get_state(meter)

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

  test "emits received lines even when no exchange is active" do
    {:ok, meter} = start_meter()

    {:off, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Channel1: -0.0000006 ")

    assert_receive {:admx3652, ^meter,
                    {:line,
                     %Line{
                       direction: :received,
                       raw: "Channel1: -0.0000006 ",
                       timestamp: timestamp,
                       decoded: {:measurement, 1, value},
                       exchange_id: nil
                     }}}

    assert is_integer(timestamp)
    assert value == -0.0000006
  end

  test "emits unsolicited measurements as readings without request metadata" do
    {:ok, meter} = start_meter()

    {:off, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Channel2: 1.25")

    assert_reading(%Reading{
      channel: 2,
      value: 1.25,
      expected: nil
    })

    assert_line(%Line{decoded: {:measurement, 2, 1.25}})
  end

  test "correlates a manual measurement and emits it before its line" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.measure(meter, 1) end)

    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert_line(%Line{
      direction: :sent,
      raw: "MEASure:VOLTage:DC? 1",
      exchange_id: exchange_id,
      timestamp: sent_at
    })

    assert_line(%Line{direction: :sent, raw: "SYSTem:ERRor?", exchange_id: ^exchange_id})

    assert {:ready,
            %Data{
              transport: transport,
              expected: %{
                1 =>
                  %ExpectedReading{
                    exchange_id: ^exchange_id,
                    sent_at: ^sent_at,
                    expected_after: expected_after
                  } = expected
              }
            }} = :sys.get_state(meter)

    assert expected_after - sent_at ==
             System.convert_time_unit(403_000, :microsecond, :native)

    TestTransport.send_line(transport, "Channel1: 1.25")

    assert_reading(%Reading{
      channel: 1,
      value: 1.25,
      expected: ^expected,
      timestamp: received_at
    })

    assert_line(%Line{
      decoded: {:measurement, 1, 1.25},
      timestamp: ^received_at,
      exchange_id: nil
    })

    assert {:ready, %Data{expected: %{}}} = :sys.get_state(meter)

    TestTransport.send_line(transport, ~s(0,"No error"))
    assert_line(%Line{decoded: {:error_queue, 0, "No error"}, exchange_id: ^exchange_id})
    assert {:ok, ^expected} = Task.await(task)
  end

  test "a raw command from ready is emitted without an exchange id and desynchronises" do
    {:ok, meter} = start_ready_meter()

    assert ADMX3652.raw_command(meter, "SYSTem:VERSion?") == :ok

    assert_receive {:transport_write, "SYSTem:VERSion?"}

    assert_line(%Line{
      direction: :sent,
      raw: "SYSTem:VERSion?",
      decoded: nil,
      exchange_id: nil
    })

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

  test "emits sent and claimed lines with one exchange id" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_line(%Line{
      direction: :sent,
      raw: "CONFigure:VOLTage:DC? 1",
      decoded: nil,
      exchange_id: exchange_id
    })

    assert is_reference(exchange_id)

    assert_line(%Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      decoded: nil,
      exchange_id: ^exchange_id
    })

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_line(%Line{
      direction: :received,
      raw: "CHAN[1]-RANGE: 2.000000",
      decoded: {:range, 1, 2.0},
      exchange_id: ^exchange_id
    })

    assert_line(%Line{
      direction: :received,
      raw: ~s(0,"No error"),
      decoded: {:error_queue, 0, "No error"},
      exchange_id: ^exchange_id
    })

    assert Task.await(task) == {:ok, 2.0}
  end

  test "does not label a received line rejected as invalid by the exchange" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_line(%Line{direction: :sent})
    assert_line(%Line{direction: :sent})

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")

    assert_line(%Line{direction: :received, exchange_id: exchange_id})

    assert is_reference(exchange_id)

    TestTransport.send_line(transport, "CHAN[1]-RANGE: 3.000000")

    assert_line(%Line{
      direction: :received,
      raw: "CHAN[1]-RANGE: 3.000000",
      exchange_id: nil
    })

    assert Task.await(task) ==
             {:error, {:protocol, {:command_response, :duplicate_range_response}}}

    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)
  end

  test "interleaves follow-up writes into the emitted line stream" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.set_range(meter, 1, 2.0) end)

    assert_line(%Line{
      direction: :sent,
      raw: "CONFigure:VOLTage:DC 1,2.0",
      exchange_id: exchange_id
    })

    assert_line(%Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      exchange_id: ^exchange_id
    })

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(-224,"Illegal parameter value"))

    assert_line(%Line{
      direction: :received,
      decoded: {:error_queue, -224, "Illegal parameter value"},
      exchange_id: ^exchange_id
    })

    assert_line(%Line{
      direction: :sent,
      raw: "SYSTem:ERRor?",
      exchange_id: ^exchange_id
    })

    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_line(%Line{
      direction: :received,
      decoded: {:error_queue, 0, "No error"},
      exchange_id: ^exchange_id
    })

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
    defaults = [
      transport: TestTransport,
      transport_opts: [test: self()],
      event_target: self()
    ]

    ADMX3652.start_link(Keyword.merge(defaults, opts))
  end

  defp start_ready_meter(opts \\ []) do
    with {:ok, meter} <- start_meter(opts) do
      :sys.replace_state(meter, fn {_state, data} -> {:ready, data} end)
      {:ok, meter}
    end
  end
end
