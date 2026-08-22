defmodule ADMX3652.Configuration do
  @moduledoc """
  Desired instrument configuration applied after every startup.

  Settings which the ADMX3652 cannot report back are always present. NPLC may
  be supplied independently for either channel, and the trigger source may be
  supplied or left as `nil`; omitted readable settings are queried while the
  driver is configuring.
  """

  alias ADMX3652.Command

  defstruct line_frequency: 50,
            configured_range: %{1 => :auto, 2 => :auto},
            read_mode: %{1 => :single, 2 => :single},
            nplc: %{},
            trigger_source: nil

  @type t :: %__MODULE__{
          line_frequency: Command.line_frequency(),
          configured_range: %{required(1) => Command.range(), required(2) => Command.range()},
          read_mode: %{required(1) => Command.read_mode(), required(2) => Command.read_mode()},
          nplc: %{optional(1 | 2) => Command.nplc()},
          trigger_source: Command.trigger_source() | nil
        }

  @doc "Returns the conservative built-in configuration."
  @spec default() :: t()
  def default, do: %__MODULE__{}

  @doc false
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = configuration) do
    with :ok <- validate_line_frequency(configuration.line_frequency),
         :ok <-
           validate_channel_map(
             :configured_range,
             configuration.configured_range,
             &Command.valid_range?/1
           ),
         :ok <-
           validate_channel_map(:read_mode, configuration.read_mode, &Command.valid_read_mode?/1),
         :ok <- validate_nplc(configuration.nplc),
         :ok <- validate_trigger_source(configuration.trigger_source),
         :ok <- validate_external_read_modes(configuration) do
      :ok
    end
  end

  def validate(other), do: {:error, {:expected_configuration, other}}

  @doc false
  @spec commands(t()) :: [Command.t()]
  def commands(%__MODULE__{} = configuration) do
    [
      Command.set_line_frequency(configuration.line_frequency),
      Command.set_range(1, configuration.configured_range[1]),
      Command.set_range(2, configuration.configured_range[2]),
      Command.set_read_mode(1, configuration.read_mode[1]),
      Command.set_read_mode(2, configuration.read_mode[2]),
      configured_or_query_nplc(configuration, 1),
      configured_or_query_nplc(configuration, 2),
      configured_or_query_trigger_source(configuration)
    ]
  end

  defp configured_or_query_nplc(configuration, channel) do
    case Map.fetch(configuration.nplc, channel) do
      {:ok, nplc} -> Command.set_nplc(channel, nplc)
      :error -> Command.get_nplc(channel)
    end
  end

  defp configured_or_query_trigger_source(%{trigger_source: nil}),
    do: Command.get_trigger_source()

  defp configured_or_query_trigger_source(%{trigger_source: trigger_source}),
    do: Command.set_trigger_source(trigger_source)

  defp validate_line_frequency(value) do
    if Command.valid_line_frequency?(value),
      do: :ok,
      else: {:error, {:invalid_line_frequency, value}}
  end

  defp validate_channel_map(name, values, predicate) when is_map(values) do
    if Map.keys(values) |> Enum.sort() == [1, 2] and
         Enum.all?(values, fn {_channel, value} -> predicate.(value) end) do
      :ok
    else
      {:error, {:invalid_channel_map, name, values}}
    end
  end

  defp validate_channel_map(name, values, _predicate),
    do: {:error, {:invalid_channel_map, name, values}}

  defp validate_nplc(values) when is_map(values) do
    if Enum.all?(values, fn {channel, value} ->
         channel in [1, 2] and Command.valid_nplc?(value)
       end) do
      :ok
    else
      {:error, {:invalid_nplc, values}}
    end
  end

  defp validate_nplc(values), do: {:error, {:invalid_nplc, values}}

  defp validate_trigger_source(nil), do: :ok

  defp validate_trigger_source(value) do
    if Command.valid_trigger_source?(value),
      do: :ok,
      else: {:error, {:invalid_trigger_source, value}}
  end

  defp validate_external_read_modes(%{
         trigger_source: :external,
         read_mode: %{1 => mode_1, 2 => mode_2}
       })
       when mode_1 != mode_2,
       do: {:error, :mixed_external_read_modes}

  defp validate_external_read_modes(_configuration), do: :ok
end
