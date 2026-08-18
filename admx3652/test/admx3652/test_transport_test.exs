defmodule ADMX3652.TestTransportTest do
  use ExUnit.Case, async: true

  alias ADMX3652.TestTransport

  setup do
    {:ok, transport} = TestTransport.start_link(self(), test: self())
    %{transport: transport}
  end

  test "reports writes to the test process", %{transport: transport} do
    assert :ok = TestTransport.write(transport, ["MEASure", ??, ?\n])
    assert_receive {:transport_write, ["MEASure", ??, ?\n]}
  end

  test "reports enabled state changes to the test process", %{transport: transport} do
    assert :ok = TestTransport.set_enabled(transport, true)
    assert_receive {:transport_enabled, true}
  end

  test "sends incoming lines to the owner", %{transport: transport} do
    assert :ok = TestTransport.send_line(transport, "42")
    assert_receive {:admx3652_transport, ^transport, {:line, "42"}}
  end

  test "sends transport errors to the owner", %{transport: transport} do
    assert :ok = TestTransport.send_error(transport, :disconnected)
    assert_receive {:admx3652_transport, ^transport, {:error, :disconnected}}
  end
end
