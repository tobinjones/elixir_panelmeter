defmodule ADMX3652.ExchangeTest do
  use ExUnit.Case, async: true

  alias ADMX3652.{Command, Exchange}

  test "starts a query and its error pop together" do
    {exchange, writes} = Exchange.start(Command.get_range(1))

    assert %Exchange{response: nil} = exchange

    assert Enum.map(writes, &IO.iodata_to_binary/1) ==
             ["CONFigure:VOLTage:DC? 1", "SYSTem:ERRor?"]
  end

  test "completes after both the primary response and clean error sentinel" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert {:continue, exchange, []} =
             Exchange.offer(exchange, {:range, 1, 2.0})

    assert {:complete, {:ok, 2.0}, :none} =
             Exchange.offer(exchange, {:error_queue, 0, "No error"})
  end

  test "a silent setter is provisional until the clean error sentinel" do
    {exchange, writes} = Exchange.start(Command.set_range(1, 2.0))

    assert %Exchange{response: nil} = exchange
    assert length(writes) == 2

    assert {:complete, :ok, {:set_range, 1, 2.0}} =
             Exchange.offer(exchange, {:error_queue, 0, "No error"})
  end

  test "drains and reports errors even when a query has no primary response" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert {:continue, exchange, ["SYSTem:ERRor?"]} =
             Exchange.offer(exchange, {:error_queue, -200, "Execution error"})

    assert {:complete, {:error, {:device, [{-200, "Execution error"}]}}, :none} =
             Exchange.offer(exchange, {:error_queue, 0, "No error"})
  end

  test "drains multiple errors in queue order" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert {:continue, exchange, ["SYSTem:ERRor?"]} =
             Exchange.offer(exchange, {:error_queue, -101, "Invalid character"})

    assert {:continue, exchange, ["SYSTem:ERRor?"]} =
             Exchange.offer(exchange, {:error_queue, -200, "Execution error"})

    assert {:complete,
            {:error,
             {:device,
              [
                {-101, "Invalid character"},
                {-200, "Execution error"}
              ]}}, :none} =
             Exchange.offer(exchange, {:error_queue, 0, "No error"})
  end

  test "a clean sentinel without the promised range response is invalid" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert {:invalid, :missing_range_response} =
             Exchange.offer(exchange, {:error_queue, 0, "No error"})
  end

  test "does not claim interleaved messages" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert :not_claimed = Exchange.offer(exchange, {:measurement, 2, 1.25})
  end

  test "rejects a duplicate claimed response" do
    {exchange, _writes} = Exchange.start(Command.get_range(1))

    assert {:continue, exchange, []} =
             Exchange.offer(exchange, {:range, 1, 2.0})

    assert {:invalid, {:command_response, :duplicate_range_response}} =
             Exchange.offer(exchange, {:range, 1, 2.0})
  end
end
