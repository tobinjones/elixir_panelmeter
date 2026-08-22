defmodule ADMX3652.ExpectedReading do
  @moduledoc """
  A reading the driver has asked the instrument to produce.

  `sent_at` is the monotonic time at which the measurement command was sent.
  `expected_after` is the earliest predicted completion time derived from the
  aperture in force. Both values use the VM's native monotonic time unit and
  are meaningful only within the running VM.

  The same struct returned by `ADMX3652.measure/2` is included in the eventual
  `ADMX3652.Reading`, allowing callers to match the reading to its request.
  """

  alias ADMX3652.{Exchange, Protocol, Shadow}

  @enforce_keys [:channel, :exchange_id, :sent_at, :expected_after]
  defstruct [:channel, :exchange_id, :sent_at, :expected_after]

  @type t :: %__MODULE__{
          channel: Protocol.channel(),
          exchange_id: Exchange.id(),
          sent_at: integer(),
          expected_after: integer()
        }

  @spec new(Protocol.channel(), Exchange.id(), integer(), Shadow.t()) :: t()
  def new(channel, exchange_id, sent_at, %Shadow{} = shadow) do
    duration = Shadow.conversion_time(shadow, channel)

    %__MODULE__{
      channel: channel,
      exchange_id: exchange_id,
      sent_at: sent_at,
      expected_after: sent_at + duration
    }
  end
end
