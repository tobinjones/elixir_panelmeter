defmodule ADMX3652.ExpectedReading do
  @moduledoc false

  alias ADMX3652.{Exchange, Protocol, Shadow}

  @enforce_keys [:channel, :exchange_id, :sent_at, :expected_at]
  defstruct [:channel, :exchange_id, :sent_at, :expected_at]

  @type t :: %__MODULE__{
          channel: Protocol.channel(),
          exchange_id: Exchange.id(),
          sent_at: integer(),
          expected_at: integer()
        }

  @spec new(Protocol.channel(), Exchange.id(), integer(), Shadow.t()) :: t()
  def new(channel, exchange_id, sent_at, %Shadow{} = shadow) do
    duration = Shadow.conversion_time(shadow, channel)

    %__MODULE__{
      channel: channel,
      exchange_id: exchange_id,
      sent_at: sent_at,
      expected_at: sent_at + duration
    }
  end
end
