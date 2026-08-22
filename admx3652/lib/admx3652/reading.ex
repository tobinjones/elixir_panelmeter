defmodule ADMX3652.Reading do
  @moduledoc """
  An asynchronous reading received from the ADMX3652.

  Manual readings carry the originating exchange ID and the monotonic times
  at which they were requested and expected. Continuous or otherwise
  unsolicited readings leave those fields as `nil`.
  """

  alias ADMX3652.{Exchange, Protocol}

  @enforce_keys [:channel, :value, :timestamp]
  defstruct [:channel, :value, :timestamp, :exchange_id, :requested_at, :expected_at]

  @type t :: %__MODULE__{
          channel: Protocol.channel(),
          value: float() | :overload,
          timestamp: integer(),
          exchange_id: Exchange.id() | nil,
          requested_at: integer() | nil,
          expected_at: integer() | nil
        }
end
