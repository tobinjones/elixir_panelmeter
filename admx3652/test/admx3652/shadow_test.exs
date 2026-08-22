defmodule ADMX3652.ShadowTest do
  use ExUnit.Case, async: true

  alias ADMX3652.Shadow

  test "applies a verified configured range" do
    shadow = Shadow.apply(%Shadow{}, {:set_range, 1, :auto})

    assert shadow.configured_range == %{1 => :auto, 2 => :unknown}
  end

  test "does not change for an empty delta" do
    shadow = %Shadow{}
    assert Shadow.apply(shadow, :none) == shadow
  end

  test "becomes complete after all configuration values are applied" do
    shadow =
      %Shadow{}
      |> Shadow.apply({:set_line_frequency, 50})
      |> Shadow.apply({:set_range, 1, :auto})
      |> Shadow.apply({:set_range, 2, 20.0})
      |> Shadow.apply({:set_read_mode, 1, :single})
      |> Shadow.apply({:set_read_mode, 2, :single})
      |> Shadow.apply({:set_nplc, 1, 10.0})
      |> Shadow.apply({:set_nplc, 2, 10.0})
      |> Shadow.apply({:set_trigger_source, :internal})

    assert Shadow.complete?(shadow)
    refute Shadow.complete?(%{shadow | trigger_source: :unknown})
  end
end
