defmodule ADMX3652.ConfigurationTest do
  use ExUnit.Case, async: true

  alias ADMX3652.{Command, Configuration}

  test "provides a complete safe default and queries readable settings" do
    configuration = Configuration.default()

    assert configuration == %Configuration{
             line_frequency: 50,
             configured_range: %{1 => :auto, 2 => :auto},
             read_mode: %{1 => :single, 2 => :single},
             nplc: %{},
             trigger_source: nil
           }

    assert Configuration.validate(configuration) == :ok

    assert Configuration.commands(configuration) == [
             Command.set_line_frequency(50),
             Command.set_range(1, :auto),
             Command.set_range(2, :auto),
             Command.set_read_mode(1, :single),
             Command.set_read_mode(2, :single),
             Command.get_nplc(1),
             Command.get_nplc(2),
             Command.get_trigger_source()
           ]
  end

  test "allows readable settings to be supplied independently" do
    configuration = %Configuration{nplc: %{2 => 0.5}, trigger_source: :internal}

    assert Configuration.validate(configuration) == :ok

    assert Enum.slice(Configuration.commands(configuration), 5, 3) == [
             Command.get_nplc(1),
             Command.set_nplc(2, 0.5),
             Command.set_trigger_source(:internal)
           ]
  end

  test "rejects missing non-readable channel settings" do
    configuration = %Configuration{configured_range: %{1 => :auto}}

    assert {:error, {:invalid_channel_map, :configured_range, %{1 => :auto}}} =
             Configuration.validate(configuration)
  end

  test "rejects mixed read modes with an explicit external trigger" do
    configuration = %Configuration{
      trigger_source: :external,
      read_mode: %{1 => :single, 2 => :continuous}
    }

    assert Configuration.validate(configuration) == {:error, :mixed_external_read_modes}
  end
end
