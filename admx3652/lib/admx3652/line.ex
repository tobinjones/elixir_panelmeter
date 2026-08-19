defmodule ADMX3652.Line do
  @moduledoc """
  A complete line received from the ADMX3652.

  `raw` preserves exactly what the transport delivered. `timestamp` is a
  monotonic native-time value recorded when the owning `ADMX3652` process
  handles the line, and `decoded` is the pure protocol classification.

  The timestamp is useful for ordering and elapsed-time calculations within a
  running VM. It is not a wall-clock time and is not meaningful across boots.
  """

  alias ADMX3652.Protocol

  @enforce_keys [:raw, :timestamp, :decoded]
  defstruct [:raw, :timestamp, :decoded]

  @type t :: %__MODULE__{
          raw: binary(),
          timestamp: integer(),
          decoded: Protocol.decoded()
        }
end
