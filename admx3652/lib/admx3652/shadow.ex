defmodule ADMX3652.Shadow do
  @moduledoc """
  Driver state known to have been accepted by the ADMX3652.

  It contains only configuration values verified by a successful exchange.
  """

  alias ADMX3652.Command

  defstruct line_frequency: :unknown,
            configured_range: %{1 => :unknown, 2 => :unknown},
            read_mode: %{1 => :unknown, 2 => :unknown},
            nplc: %{1 => :unknown, 2 => :unknown},
            trigger_source: :unknown

  @type t :: %__MODULE__{
          line_frequency: Command.line_frequency() | :unknown,
          configured_range: %{1 => Command.range() | :unknown, 2 => Command.range() | :unknown},
          read_mode: %{1 => Command.read_mode() | :unknown, 2 => Command.read_mode() | :unknown},
          nplc: %{1 => Command.nplc() | :unknown, 2 => Command.nplc() | :unknown},
          trigger_source: Command.trigger_source() | :unknown
        }

  @spec apply(t(), Command.shadow_delta()) :: t()
  def apply(shadow, :none), do: shadow

  def apply(shadow, {:set_range, channel, range}) do
    configured_range = Map.put(shadow.configured_range, channel, range)
    %{shadow | configured_range: configured_range}
  end

  def apply(shadow, {:set_nplc, channel, nplc}) do
    %{shadow | nplc: Map.put(shadow.nplc, channel, nplc)}
  end

  def apply(shadow, {:set_line_frequency, frequency}) do
    %{shadow | line_frequency: frequency}
  end

  def apply(shadow, {:set_read_mode, channel, mode}) do
    %{shadow | read_mode: Map.put(shadow.read_mode, channel, mode)}
  end

  def apply(shadow, {:set_trigger_source, source}) do
    %{shadow | trigger_source: source}
  end

  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{} = shadow) do
    shadow.line_frequency != :unknown and
      Enum.all?(shadow.configured_range, fn {_channel, value} -> value != :unknown end) and
      Enum.all?(shadow.read_mode, fn {_channel, value} -> value != :unknown end) and
      Enum.all?(shadow.nplc, fn {_channel, value} -> value != :unknown end) and
      shadow.trigger_source != :unknown
  end
end
