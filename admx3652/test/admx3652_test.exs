defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.{Data, Line, Shadow, TestLinePublisher, TestTransport}

  test "starts in :off and starts its transport" do
    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self()]
             )

    assert {:off,
            %ADMX3652.Data{
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
               transport_opts: [test: self()]
             )

    assert Process.whereis(name) == meter
  end

  test "starts in :desynchronised when the transport is already enabled" do
    assert {:ok, meter} =
             ADMX3652.start_link(
               transport: TestTransport,
               transport_opts: [test: self(), enabled: true]
             )

    assert {:desynchronised, %ADMX3652.Data{}} = :sys.get_state(meter)
  end

  test "rejects commands while off" do
    {:ok, meter} = start_meter()

    assert ADMX3652.get_range(meter, 1) == {:error, :off}
  end

  test "publishes received lines even when no exchange is active" do
    {:ok, meter} = start_meter(line_publisher: {TestLinePublisher, self()})

    {:off, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "Channel1: -0.0000006 ")

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      raw: "Channel1: -0.0000006 ",
                      timestamp: timestamp,
                      decoded: {:measurement, 1, value},
                      exchange_id: nil
                    }}

    assert is_integer(timestamp)
    assert value == -0.0000006
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
    {:ok, meter} =
      start_ready_meter(line_publisher: {TestLinePublisher, self()})

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_receive {:published_line,
                    %Line{
                      direction: :sent,
                      raw: "CONFigure:VOLTage:DC? 1",
                      decoded: nil,
                      exchange_id: exchange_id
                    }}

    assert is_reference(exchange_id)

    assert_receive {:published_line,
                    %Line{
                      direction: :sent,
                      raw: "SYSTem:ERRor?",
                      decoded: nil,
                      exchange_id: ^exchange_id
                    }}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")
    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      raw: "CHAN[1]-RANGE: 2.000000",
                      decoded: {:range, 1, 2.0},
                      exchange_id: ^exchange_id
                    }}

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      raw: ~s(0,"No error"),
                      decoded: {:error_queue, 0, "No error"},
                      exchange_id: ^exchange_id
                    }}

    assert Task.await(task) == {:ok, 2.0}
  end

  test "does not label a received line rejected as invalid by the exchange" do
    {:ok, meter} =
      start_ready_meter(line_publisher: {TestLinePublisher, self()})

    task = Task.async(fn -> ADMX3652.get_range(meter, 1) end)

    assert_receive {:published_line, %Line{direction: :sent}}
    assert_receive {:published_line, %Line{direction: :sent}}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, "CHAN[1]-RANGE: 2.000000")

    assert_receive {:published_line, %Line{direction: :received, exchange_id: exchange_id}}

    assert is_reference(exchange_id)

    TestTransport.send_line(transport, "CHAN[1]-RANGE: 3.000000")

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      raw: "CHAN[1]-RANGE: 3.000000",
                      exchange_id: nil
                    }}

    assert Task.await(task) ==
             {:error, {:protocol, {:command_response, :duplicate_range_response}}}

    assert {:desynchronised, %Data{shadow: :unknown}} = :sys.get_state(meter)
  end

  test "interleaves follow-up writes into the published line stream" do
    {:ok, meter} =
      start_ready_meter(line_publisher: {TestLinePublisher, self()})

    task = Task.async(fn -> ADMX3652.set_range(meter, 1, 2.0) end)

    assert_receive {:published_line,
                    %Line{
                      direction: :sent,
                      raw: "CONFigure:VOLTage:DC 1,2.0",
                      exchange_id: exchange_id
                    }}

    assert_receive {:published_line,
                    %Line{
                      direction: :sent,
                      raw: "SYSTem:ERRor?",
                      exchange_id: ^exchange_id
                    }}

    {:ready, %Data{transport: transport}} = :sys.get_state(meter)
    TestTransport.send_line(transport, ~s(-224,"Illegal parameter value"))

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      decoded: {:error_queue, -224, "Illegal parameter value"},
                      exchange_id: ^exchange_id
                    }}

    assert_receive {:published_line,
                    %Line{
                      direction: :sent,
                      raw: "SYSTem:ERRor?",
                      exchange_id: ^exchange_id
                    }}

    TestTransport.send_line(transport, ~s(0,"No error"))

    assert_receive {:published_line,
                    %Line{
                      direction: :received,
                      decoded: {:error_queue, 0, "No error"},
                      exchange_id: ^exchange_id
                    }}

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
      transport_opts: [test: self()]
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
