defmodule ADMX3652.Reading do
  @moduledoc """
  An asynchronous reading received from the ADMX3652.

  A requested reading carries the exact `ADMX3652.ExpectedReading` returned by
  `ADMX3652.measure/2`. Continuous or otherwise unsolicited readings leave
  `expected` as `nil`.
  """

  alias ADMX3652.{ExpectedReading, Protocol}

  @enforce_keys [:channel, :value, :timestamp]
  defstruct [:channel, :value, :timestamp, :expected]

  @type t :: %__MODULE__{
          channel: Protocol.channel(),
          value: float() | :overload,
          timestamp: integer(),
          expected: ExpectedReading.t() | nil
        }
end
