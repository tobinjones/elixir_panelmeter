defmodule ADMX3652.TransactionTest do
  use ExUnit.Case, async: true

  alias ADMX3652.{Command, Transaction}

  test "starts a query and its error pop together" do
    {transaction, writes} = Transaction.start(Command.get_range(1))

    assert %Transaction{primary: {:awaiting, {:await_range, 1}}} = transaction

    assert Enum.map(writes, &IO.iodata_to_binary/1) ==
             ["CONFigure:VOLTage:DC? 1", "SYSTem:ERRor?"]
  end

  test "completes after both the primary response and clean error sentinel" do
    {transaction, _writes} = Transaction.start(Command.get_range(1))

    assert {:continue, transaction, []} =
             Transaction.offer(transaction, {:range, 1, 2.0})

    assert {:complete, {:ok, 2.0}, :none} =
             Transaction.offer(transaction, {:error_queue, 0, "No error"})
  end

  test "a silent setter is provisional until the clean error sentinel" do
    {transaction, writes} = Transaction.start(Command.set_range(1, 2.0))

    assert %Transaction{primary: {:done, :ok, {:set_range, 1, 2.0}}} = transaction
    assert length(writes) == 2

    assert {:complete, :ok, {:set_range, 1, 2.0}} =
             Transaction.offer(transaction, {:error_queue, 0, "No error"})
  end

  test "drains and reports errors even when a query has no primary response" do
    {transaction, _writes} = Transaction.start(Command.get_range(1))

    assert {:continue, transaction, ["SYSTem:ERRor?"]} =
             Transaction.offer(transaction, {:error_queue, -200, "Execution error"})

    assert {:complete, {:error, {:device, [{-200, "Execution error"}]}}, :none} =
             Transaction.offer(transaction, {:error_queue, 0, "No error"})
  end

  test "drains multiple errors in queue order" do
    {transaction, _writes} = Transaction.start(Command.get_range(1))

    assert {:continue, transaction, ["SYSTem:ERRor?"]} =
             Transaction.offer(transaction, {:error_queue, -101, "Invalid character"})

    assert {:continue, transaction, ["SYSTem:ERRor?"]} =
             Transaction.offer(transaction, {:error_queue, -200, "Execution error"})

    assert {:complete,
            {:error,
             {:device,
              [
                {-101, "Invalid character"},
                {-200, "Execution error"}
              ]}}, :none} =
             Transaction.offer(transaction, {:error_queue, 0, "No error"})
  end

  test "a clean sentinel without the promised query response is invalid" do
    {transaction, _writes} = Transaction.start(Command.get_range(1))

    assert {:invalid, :missing_primary_response} =
             Transaction.offer(transaction, {:error_queue, 0, "No error"})
  end

  test "does not claim interleaved messages" do
    {transaction, _writes} = Transaction.start(Command.get_range(1))

    assert :not_claimed = Transaction.offer(transaction, {:measurement, 2, 1.25})
  end
end
