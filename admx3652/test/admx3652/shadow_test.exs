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
end
