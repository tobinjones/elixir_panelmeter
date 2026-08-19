defmodule ADMX3652.CommandTest do
  use ExUnit.Case, async: true

  alias ADMX3652.Command

  test "prepares a range query that awaits a matching response" do
    command = Command.get_range(1)

    assert {:await, {:await_range, 1}, write} = Command.prepare(command)
    assert IO.iodata_to_binary(write) == "CONFigure:VOLTage:DC? 1"

    assert Command.offer(command, {:await_range, 1}, {:range, 1, 2.0}) ==
             {:done, {:ok, 2.0}, :none}

    assert Command.offer(command, {:await_range, 1}, {:measurement, 1, 1.0}) ==
             :not_claimed
  end

  test "prepares a silent range setter with a provisional shadow change" do
    command = Command.set_range(2, :auto)

    assert {:done, :ok, {:set_range, 2, :auto}, write} = Command.prepare(command)
    assert IO.iodata_to_binary(write) == "CONFigure:VOLTage:DC 2,AUTO"
  end
end
