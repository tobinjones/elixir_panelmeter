defmodule ADMX3652Test do
  use ExUnit.Case, async: true

  alias ADMX3652.TestTransport

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
end
