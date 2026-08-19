defmodule ADMX3652.Shadow do
  @moduledoc """
  Driver state known to have been accepted by the ADMX3652.

  This is deliberately limited to configured range while the transaction and
  shadow-state boundary is being established. More settings are not
  implemented yet.
  """

  alias ADMX3652.Command

  defstruct configured_range: %{1 => :unknown, 2 => :unknown}

  @type t :: %__MODULE__{
          configured_range: %{1 => Command.range() | :unknown, 2 => Command.range() | :unknown}
        }

  @spec apply(t(), Command.shadow_delta()) :: t()
  def apply(shadow, :none), do: shadow

  def apply(shadow, {:set_range, channel, range}) do
    configured_range = Map.put(shadow.configured_range, channel, range)
    %{shadow | configured_range: configured_range}
  end
end
