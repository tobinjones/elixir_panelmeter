defmodule ADMX3652.Shadow do
  @moduledoc """
  Driver state known to have been accepted by the ADMX3652.

  The initial values describe the instrument's documented reset defaults.
  """

  alias ADMX3652.Command

  defstruct configured_range: %{1 => :unknown, 2 => :unknown},
            nplc: %{1 => 10.0, 2 => 10.0},
            line_frequency: 50

  @type t :: %__MODULE__{
          configured_range: %{1 => Command.range() | :unknown, 2 => Command.range() | :unknown},
          nplc: %{1 => float(), 2 => float()},
          line_frequency: 50 | 60
        }

  @spec conversion_time(t(), 1 | 2) :: integer()
  def conversion_time(%__MODULE__{} = shadow, channel) when channel in [1, 2] do
    microseconds = conversion_time_us(shadow.nplc[channel], shadow.line_frequency)
    System.convert_time_unit(microseconds, :microsecond, :native)
  end

  @spec apply(t(), Command.shadow_delta()) :: t()
  def apply(shadow, :none), do: shadow

  def apply(shadow, {:set_range, channel, range}) do
    configured_range = Map.put(shadow.configured_range, channel, range)
    %{shadow | configured_range: configured_range}
  end

  defp conversion_time_us(0.05, _line_frequency), do: 4_000
  defp conversion_time_us(0.1, _line_frequency), do: 5_000
  defp conversion_time_us(0.25, _line_frequency), do: 8_000
  defp conversion_time_us(0.5, _line_frequency), do: 13_000

  defp conversion_time_us(nplc, line_frequency) when nplc >= 1 do
    ceil(2 * nplc / line_frequency * 1_000_000 + 3_000)
  end
end
