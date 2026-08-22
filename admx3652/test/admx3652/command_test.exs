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
    assert {:ok, :ok, {:set_read_mode, 1, :single}} = Command.finish(command, nil)
  end

  test "describes NPLC queries and setters" do
    query = Command.get_nplc(1)

    assert {nil, "CONFigure:VOLTage:DC:NPLCycles? 1"} = Command.prepare(query)
    assert {:claimed, 0.5} = Command.claim(query, nil, {:nplc, 1, 0.5})
    assert {:ok, {:ok, 0.5}, {:set_nplc, 1, 0.5}} = Command.finish(query, 0.5)
    assert {:error, :missing_nplc_response} = Command.finish(query, nil)

    setter = Command.set_nplc(2, 3.5)
    assert {nil, "CONFigure:VOLTage:DC:NPLCycles 2,3.5"} = Command.prepare(setter)
    assert {:ok, :ok, {:set_nplc, 2, 3.5}} = Command.finish(setter, nil)
  end

  test "accepts only the documented sub-one NPLC values" do
    for nplc <- [0.05, 0.1, 0.25, 0.5, 1, 3.5, 1_000] do
      assert {:set_nplc, 1, value} = Command.set_nplc(1, nplc)
      assert value == nplc
    end

    for nplc <- [-1, 0, 0.2, 0.75] do
      assert_raise ArgumentError, fn -> Command.set_nplc(1, nplc) end
    end
  end

  test "describes silent measurement configuration setters" do
    line_frequency = Command.set_line_frequency(60)
    assert {nil, "SYSTem:PLC:SET 60"} = Command.prepare(line_frequency)
    assert {:ok, :ok, {:set_line_frequency, 60}} = Command.finish(line_frequency, nil)

    continuous = Command.set_read_mode(1, :continuous)
    assert {nil, "CONFigure:CONTINUOUS:READ 1,ON"} = Command.prepare(continuous)
    assert {:ok, :ok, {:set_read_mode, 1, :continuous}} = Command.finish(continuous, nil)

    single = Command.set_read_mode(2, :single)
    assert {nil, "CONFigure:CONTINUOUS:READ 2,OFF"} = Command.prepare(single)
  end

  test "describes trigger source queries and setters" do
    query = Command.get_trigger_source()

    assert {nil, "TRIGger:SOURce?"} = Command.prepare(query)

    assert {:claimed, :external} =
             Command.claim(query, nil, {:trigger_source, :external})

    assert {:ok, {:ok, :external}, {:set_trigger_source, :external}} =
             Command.finish(query, :external)

    setter = Command.set_trigger_source(:internal)
    assert {nil, "TRIGger:SOURce INTernal"} = Command.prepare(setter)
    assert {:ok, :ok, {:set_trigger_source, :internal}} = Command.finish(setter, nil)
  end

  test "rejects a duplicate range response" do
    command = Command.get_range(1)

    assert {:invalid, :duplicate_range_response} =
             Command.claim(command, 2.0, {:range, 1, 2.0})
  end

  test "gets and sets NPLC" do
    get = Command.get_nplc(1)
    set = Command.set_nplc(2, 10)

    assert Command.prepare(get) == {nil, "CONFigure:VOLTage:DC:NPLCycles? 1"}
    assert Command.claim(get, nil, {:nplc, 1, 0.5}) == {:claimed, 0.5}
    assert Command.finish(get, 0.5) == {:ok, {:ok, 0.5}, {:set_nplc, 1, 0.5}}

    assert Command.prepare(set) == {nil, "CONFigure:VOLTage:DC:NPLCycles 2,10.0"}
    assert Command.finish(set, nil) == {:ok, :ok, {:set_nplc, 2, 10.0}}
  end

  test "describes line frequency and read mode setters" do
    assert Command.prepare(Command.set_line_frequency(60)) == {nil, "SYSTem:PLC:SET 60"}

    command = Command.set_read_mode(1, :continuous)
    assert Command.prepare(command) == {nil, "CONFigure:CONTINUOUS:READ 1,ON"}
    assert Command.finish(command, nil) == {:ok, :ok, {:set_read_mode, 1, :continuous}}
  end

  test "gets and sets trigger source" do
    get = Command.get_trigger_source()
    set = Command.set_trigger_source(:external)

    assert Command.prepare(get) == {nil, "TRIGger:SOURce?"}
    assert Command.claim(get, nil, {:trigger_source, :internal}) == {:claimed, :internal}

    assert Command.finish(get, :internal) ==
             {:ok, {:ok, :internal}, {:set_trigger_source, :internal}}

    assert Command.prepare(set) == {nil, "TRIGger:SOURce EXTernal"}
    assert Command.finish(set, nil) == {:ok, :ok, {:set_trigger_source, :external}}
  end

  test "rejects duplicate NPLC and trigger responses" do
    assert {:invalid, :duplicate_nplc_response} =
             Command.claim(Command.get_nplc(1), 10.0, {:nplc, 1, 10.0})

    assert {:invalid, :duplicate_trigger_source_response} =
             Command.claim(:get_trigger_source, :internal, {:trigger_source, :internal})
  end
end
