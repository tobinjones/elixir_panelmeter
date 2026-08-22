defmodule ADMX3652.CommandTest do
  use ExUnit.Case, async: true

  alias ADMX3652.Command

  test "accumulates and finishes a range query" do
    command = Command.get_range(1)

    assert {nil, "CONFigure:VOLTage:DC? 1"} = Command.prepare(command)
    assert {:claimed, 2.0} = Command.claim(command, nil, {:range, 1, 2.0})
    assert {:ok, {:ok, 2.0}, :none} = Command.finish(command, 2.0)

    assert {:error, :missing_range_response} = Command.finish(command, nil)

    assert Command.claim(command, nil, {:measurement, 1, 1.0}) ==
             :not_claimed
  end

  test "finishes a silent range setter at the shared sentinel" do
    command = Command.set_range(2, :auto)

    assert {nil, "CONFigure:VOLTage:DC 2,auto"} = Command.prepare(command)
    assert {:ok, :ok, {:set_range, 2, :auto}} = Command.finish(command, nil)
  end

  test "a measurement finishes independently of its asynchronous reading" do
    command = Command.measure(1)

    assert {nil, "MEASure:VOLTage:DC? 1"} = Command.prepare(command)
    assert :not_claimed = Command.claim(command, nil, {:measurement, 1, 1.25})
    assert {:ok, :ok, :none} = Command.finish(command, nil)
  end

  test "rejects a duplicate range response" do
    command = Command.get_range(1)

    assert {:invalid, :duplicate_range_response} =
             Command.claim(command, 2.0, {:range, 1, 2.0})
  end
end
