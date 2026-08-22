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

  test "calculates the expected conversion time from NPLC and line frequency" do
    shadow = %Shadow{nplc: %{1 => 10.0, 2 => 0.5}, line_frequency: 50}

    assert Shadow.conversion_time(shadow, 1) ==
             System.convert_time_unit(403_000, :microsecond, :native)

    assert Shadow.conversion_time(shadow, 2) ==
             System.convert_time_unit(13_000, :microsecond, :native)
  end
end
