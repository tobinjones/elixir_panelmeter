defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.{Data, Shadow, TestTransport}

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

  test "gets a range through a verified transaction" do
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

  test "rejects a second command while a transaction is active" do
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

  defp start_meter do
    ADMX3652.start_link(
      transport: TestTransport,
      transport_opts: [test: self()]
    )
  end

  defp start_ready_meter do
    with {:ok, meter} <- start_meter() do
      :sys.replace_state(meter, fn {_state, data} -> {:ready, data} end)
      {:ok, meter}
    end
  end
end
