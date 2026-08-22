defmodule Panelmeter.MeterEventsTest do
  use ExUnit.Case, async: true

  alias ADMX3652.{Line, Reading}

  @line_topic "admx3652:lines"
  @reading_topic "admx3652:readings"

  test "relays ordered driver events onto the firmware PubSub topics" do
    :ok = Phoenix.PubSub.subscribe(Panelmeter.PubSub, @line_topic)
    :ok = Phoenix.PubSub.subscribe(Panelmeter.PubSub, @reading_topic)

    timestamp = System.monotonic_time()
    reading = %Reading{channel: 1, value: 1.25, timestamp: timestamp}

    line = %Line{
      direction: :received,
      raw: "Channel1: 1.25",
      timestamp: timestamp,
      decoded: {:measurement, 1, 1.25}
    }

    send(Panelmeter.MeterEvents, {:admx3652, self(), {:reading, reading}})
    send(Panelmeter.MeterEvents, {:admx3652, self(), {:line, line}})

    assert_receive ^reading
    assert_receive ^line
  end
end
