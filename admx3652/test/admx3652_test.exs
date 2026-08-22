defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.{
    Configuration,
    ExpectedReading,
    Line,
    Reading,
    Shadow,
    StateMachine,
    TestTransport
  }

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

  test "rejects an invalid configuration before starting the transport" do
    configuration = %Configuration{read_mode: %{1 => :single}}

    assert {:error, {:invalid_configuration, {:invalid_channel_map, :read_mode, %{1 => :single}}}} =
             start_meter(configuration: configuration)

    refute_receive {:transport_enabled, _enabled}
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

  test "ready banner advances startup to configuring" do
    {:ok, meter} = start_meter()

    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}

    assert {:starting, %Data{transport: transport, shadow: :unknown}} =
             :sys.get_state(meter)

    TestTransport.send_line(transport, "ADC self check done")

    assert_line(%Line{
      direction: :received,
      decoded: {:device_message, :adc_self_check_done},
      exchange_id: nil
    })

    assert {:starting, %Data{}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_line(%Line{
      direction: :received,
      decoded: {:device_message, :ready},
      exchange_id: nil
    })

    assert_receive {:transport_write, "SYSTem:PLC:SET 50"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert {:configuring,
            %Data{
              current: {:configuring, _exchange},
              shadow: %Shadow{line_frequency: :unknown}
            }} = wait_for_state(meter, &match?({:ready, _data}, &1))

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

  test "reset restarts a ready meter and reapplies its configuration" do
    {:ok, meter} = start_ready_meter()

    assert ADMX3652.reset(meter) == :ok
    assert_receive {:transport_write, "*RST"}

    assert_line(%Line{
      direction: :sent,
      raw: "*RST",
      decoded: nil,
      exchange_id: nil
    })

    assert {:starting,
            %Data{
              current: nil,
              pending: [],
              expected: %{},
              shadow: :unknown,
              transport: transport
            }} =
             :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_line(%Line{decoded: {:device_message, :ready}, exchange_id: nil})
    assert_receive {:transport_write, "SYSTem:PLC:SET 50"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    assert {:configuring, %Data{current: {:configuring, _exchange}}} = :sys.get_state(meter)
  end

  test "reset interrupts an active exchange" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    assert ADMX3652.reset(meter) == :ok
    assert_receive {:transport_write, "*RST"}
    assert Task.await(task) == {:error, :reset}

    assert {:starting, %Data{current: nil, pending: [], expected: %{}, shadow: :unknown}} =
             :sys.get_state(meter)
  end

  test "reset is accepted while starting, configuring, and desynchronised" do
    {:ok, starting_meter} = start_meter()
    assert ADMX3652.enable(starting_meter) == :ok
    assert_receive {:transport_enabled, true}
    assert ADMX3652.reset(starting_meter) == :ok
    assert_receive {:transport_write, "*RST"}
    assert {:starting, %Data{shadow: :unknown}} = :sys.get_state(starting_meter)

    {:ok, configuring_meter} = start_meter()
    assert ADMX3652.enable(configuring_meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(configuring_meter)
    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_receive {:transport_write, "SYSTem:PLC:SET 50"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    assert ADMX3652.reset(configuring_meter) == :ok
    assert_receive {:transport_write, "*RST"}

    assert {:starting, %Data{current: nil, pending: [], shadow: :unknown}} =
             :sys.get_state(configuring_meter)

    {:ok, desynchronised_meter} =
      start_meter(transport_opts: [test: self(), enabled: true])

    assert ADMX3652.reset(desynchronised_meter) == :ok
    assert_receive {:transport_write, "*RST"}
    assert {:starting, %Data{shadow: :unknown}} = :sys.get_state(desynchronised_meter)
  end

  test "reset is rejected while off" do
    {:ok, meter} = start_meter()

    assert ADMX3652.reset(meter) == {:error, :off}
    refute_receive {:transport_write, "*RST"}
    assert {:off, %Data{shadow: %Shadow{}}} = :sys.get_state(meter)
  end

  test "reset write failure desynchronises the meter" do
    {:ok, meter} =
      start_meter(transport_opts: [test: self(), enabled: true, write_error: :closed])

    assert ADMX3652.reset(meter) == {:error, {:transport, :closed}}

    assert {:desynchronised, %Data{current: nil, pending: [], expected: %{}, shadow: :unknown}} =
             :sys.get_state(meter)
  end

  test "a ready banner while off remains unsolicited" do
    {:ok, meter} = start_meter()
    {:off, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_line(%Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    })

    assert {:off, %Data{}} = :sys.get_state(meter)
  end

  test "a second ready banner while configuring desynchronises the meter" do
    {:ok, meter} = start_meter()
    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_line(%Line{decoded: {:device_message, :ready}})
    assert {:configuring, %Data{}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_line(%Line{decoded: {:device_message, :ready}})
    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
  end

  test "default configuration completes the shadow before becoming ready" do
    {:ok, meter} = start_meter()

    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_line(%Line{decoded: {:device_message, :ready}})

    complete_silent_configuration_command(transport, "SYSTem:PLC:SET 50")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC 1,auto")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC 2,auto")
    complete_silent_configuration_command(transport, "CONFigure:CONTINUOUS:READ 1,OFF")
    complete_silent_configuration_command(transport, "CONFigure:CONTINUOUS:READ 2,OFF")

    assert_receive {:transport_write, "CONFigure:VOLTage:DC:NPLCycles? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    TestTransport.send_line(transport, "Channel1: 1.250000")

    assert_line(%Line{
      decoded: {:measurement, 1, 1.25},
      exchange_id: nil
    })

    TestTransport.send_line(transport, "CHAN[1]-NPLC: 10.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    complete_query_configuration_command(
      transport,
      "CONFigure:VOLTage:DC:NPLCycles? 2",
      "CHAN[2]-NPLC: 10.000000"
    )

    complete_query_configuration_command(
      transport,
      "TRIGger:SOURce?",
      "Trigger Mode : INTernal"
    )

    assert {:ready,
            %Data{
              current: nil,
              pending: [],
              shadow: %Shadow{
                line_frequency: 50,
                configured_range: %{1 => :auto, 2 => :auto},
                read_mode: %{1 => :single, 2 => :single},
                nplc: %{1 => 10.0, 2 => 10.0},
                trigger_source: :internal
              }
            }} = wait_for_state(meter, &match?({:ready, _data}, &1))
  end

  test "configured readable values are set instead of queried" do
    configuration = %ADMX3652.Configuration{
      nplc: %{1 => 1, 2 => 0.5},
      trigger_source: :internal
    }

    {:ok, meter} = start_meter(configuration: configuration)
    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    complete_silent_configuration_command(transport, "SYSTem:PLC:SET 50")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC 1,auto")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC 2,auto")
    complete_silent_configuration_command(transport, "CONFigure:CONTINUOUS:READ 1,OFF")
    complete_silent_configuration_command(transport, "CONFigure:CONTINUOUS:READ 2,OFF")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC:NPLCycles 1,1.0")
    complete_silent_configuration_command(transport, "CONFigure:VOLTage:DC:NPLCycles 2,0.5")
    complete_silent_configuration_command(transport, "TRIGger:SOURce INTernal")

    assert {:ready, %Data{shadow: %Shadow{nplc: %{1 => 1.0, 2 => 0.5}}}} =
             wait_for_state(meter, &match?({:ready, _data}, &1))
  end

  test "a configuration exchange failure desynchronises without a partial shadow" do
    {:ok, meter} = start_meter()
    assert ADMX3652.enable(meter) == :ok
    assert_receive {:transport_enabled, true}
    {:starting, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")
    assert_receive {:transport_write, "SYSTem:PLC:SET 50"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    TestTransport.send_line(transport, ~s(-200,"Execution error"))
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert {:desynchronised, %Data{current: nil, pending: [], shadow: :unknown}} =
             wait_for_state(meter, &match?({:desynchronised, _data}, &1))
  end

  test "a ready banner while ready indicates an unexpected restart" do
    {:ok, meter} = start_ready_meter()
    {:ready, %Data{transport: transport}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_line(%Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    })

    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
  end

  test "an unexpected restart interrupts an active exchange" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)
    assert_receive {:transport_write, "CONFigure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "DAQ is ready to use")

    assert_line(%Line{
      decoded: {:device_message, :ready},
      exchange_id: nil
    })

    assert Task.await(task) == {:error, :device_restarted}
    assert {:desynchronised, %Data{current: nil, shadow: :unknown}} = :sys.get_state(meter)
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

  test "gets NPLC through a verified exchange and commits it to the shadow" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_nplc(meter, 2) end)

    assert_receive {:transport_write, "CONFigure:VOLTage:DC:NPLCycles? 2"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[2]-NPLC: 0.500000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, 0.5}
    assert {:ready, %Data{shadow: %Shadow{nplc: %{2 => 0.5}}}} = :sys.get_state(meter)
  end

  test "gets trigger source through a verified exchange and commits it to the shadow" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_trigger_source(meter) end)

    assert_receive {:transport_write, "TRIGger:SOURce?"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Trigger Mode : EXTernal")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, :external}

    assert {:ready, %Data{shadow: %Shadow{trigger_source: :external}}} =
             :sys.get_state(meter)
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

  test "gets NPLC and commits the query result to shadow after verification" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_nplc(meter, 1) end)

    assert_receive {:transport_write, "CONFigure:VOLTage:DC:NPLCycles? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport, shadow: shadow}} = :sys.get_state(meter)
    assert shadow.nplc[1] == 10.0

    TestTransport.send_line(transport, "CHAN[1]-NPLC: 0.500000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, 0.5}
    assert {:ready, %Data{shadow: %Shadow{nplc: %{1 => 0.5}}}} = :sys.get_state(meter)
  end

  test "commits the remaining measurement configuration after verification" do
    {:ok, meter} = start_ready_meter()

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_nplc(meter, 2, 3.5) end,
      "CONFigure:VOLTage:DC:NPLCycles 2,3.5"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_line_frequency(meter, 60) end,
      "SYSTem:PLC:SET 60"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_read_mode(meter, 1, :single) end,
      "CONFigure:CONTINUOUS:READ 1,OFF"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_trigger_source(meter, :external) end,
      "TRIGger:SOURce EXTernal"
    )

    assert {:ready,
            %Data{
              shadow: %Shadow{
                nplc: %{2 => 3.5},
                line_frequency: 60,
                read_mode: %{1 => :single},
                trigger_source: :external
              }
            }} = :sys.get_state(meter)
  end

  test "gets and commits the trigger source" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.get_trigger_source(meter) end)

    assert_receive {:transport_write, "TRIGger:SOURce?"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Trigger Mode : EXTernal")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == {:ok, :external}

    assert {:ready, %Data{shadow: %Shadow{trigger_source: :external}}} =
             :sys.get_state(meter)
  end

  test "rejects measurement while external triggering is selected" do
    {:ok, meter} = start_ready_meter()

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_trigger_source(meter, :external) end,
      "TRIGger:SOURce EXTernal"
    )

    assert ADMX3652.measure(meter, 1) == {:error, :unsupported_trigger_mode}
    refute_receive {:transport_write, _line}
  end

  test "a repeated measurement replaces the channel expectation" do
    {:ok, meter} = start_ready_meter()

    first_task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))
    assert {:ok, first_expected} = Task.await(first_task)

    second_task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(0,"No error"))
    assert {:ok, second_expected} = Task.await(second_task)
    refute second_expected == first_expected

    TestTransport.send_line(transport, "Channel1: 1.25")
    assert_reading(%Reading{channel: 1, value: 1.25, expected: ^second_expected})
  end

  test "reconfiguration retains a requested reading expectation unchanged" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))
    assert {:ok, expected} = Task.await(task)

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_range(meter, 1, 2.0) end,
      "CONFigure:VOLTage:DC 1,2.0"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_nplc(meter, 1, 1) end,
      "CONFigure:VOLTage:DC:NPLCycles 1,1.0"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_line_frequency(meter, 60) end,
      "SYSTem:PLC:SET 60"
    )

    assert_verified_set(
      meter,
      fn -> ADMX3652.set_read_mode(meter, 1, :continuous) end,
      "CONFigure:CONTINUOUS:READ 1,ON"
    )

    assert {:ready, %Data{expected: %{1 => ^expected}}} = :sys.get_state(meter)

    TestTransport.send_line(transport, "Channel1: 1.25")
    assert_reading(%Reading{channel: 1, value: 1.25, expected: ^expected})
  end

  test "a verified trigger-source change discards requested reading expectations" do
    {:ok, meter} = start_ready_meter()

    measure_task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))
    assert {:ok, expected} = Task.await(measure_task)

    trigger_task = Task.async(fn -> ADMX3652.set_trigger_source(meter, :external) end)
    assert_receive {:transport_write, "TRIGger:SOURce EXTernal"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    assert {:ready, %Data{expected: %{1 => ^expected}}} = :sys.get_state(meter)

    TestTransport.send_line(transport, ~s(0,"No error"))
    assert Task.await(trigger_task) == :ok
    assert {:ready, %Data{expected: %{}}} = :sys.get_state(meter)
  end

  test "a rejected trigger-source change retains requested reading expectations" do
    {:ok, meter} = start_ready_meter()

    measure_task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))
    assert {:ok, expected} = Task.await(measure_task)

    trigger_task = Task.async(fn -> ADMX3652.set_trigger_source(meter, :external) end)
    assert_receive {:transport_write, "TRIGger:SOURce EXTernal"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(-200,"Execution error"))
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(trigger_task) == {:error, {:device, [{-200, "Execution error"}]}}
    assert {:ready, %Data{expected: %{1 => ^expected}}} = :sys.get_state(meter)
  end

  test "measure commits single read mode after verification" do
    {:ok, meter} = start_ready_meter()

    task = Task.async(fn -> ADMX3652.measure(meter, 1) end)
    assert_receive {:transport_write, "MEASure:VOLTage:DC? 1"}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert {:ok, %ExpectedReading{}} = Task.await(task)

    assert {:ready, %Data{shadow: %Shadow{read_mode: %{1 => :single}}}} =
             :sys.get_state(meter)
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
      :sys.replace_state(meter, fn {_state, data} ->
        shadow = %{
          data.shadow
          | line_frequency: 50,
            nplc: %{1 => 10.0, 2 => 10.0},
            trigger_source: :internal
        }

        {:ready, %{data | shadow: shadow}}
      end)

      {:ok, meter}
    end
  end

  defp complete_silent_configuration_command(transport, command) do
    assert_receive {:transport_write, ^command}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, ~s(0,"No error"))
  end

  defp complete_query_configuration_command(transport, command, response) do
    assert_receive {:transport_write, ^command}
    assert_receive {:transport_write, "SYSTem:ERRor?"}
    TestTransport.send_line(transport, response)
    TestTransport.send_line(transport, ~s(0,"No error"))
  end

  defp wait_for_state(meter, predicate, attempts \\ 100)

  defp wait_for_state(meter, predicate, attempts) when attempts > 0 do
    state = :sys.get_state(meter)

    if predicate.(state) do
      state
    else
      Process.sleep(1)
      wait_for_state(meter, predicate, attempts - 1)
    end
  end

  defp wait_for_state(meter, _predicate, 0), do: :sys.get_state(meter)

  defp assert_verified_set(meter, call, expected_write) do
    task = Task.async(call)
    assert_receive {:transport_write, ^expected_write}
    assert_receive {:transport_write, "SYSTem:ERRor?"}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert Task.await(task) == :ok
  end
end
