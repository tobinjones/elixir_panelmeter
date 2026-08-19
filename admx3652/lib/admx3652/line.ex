defmodule ADMX3652.Line do
  @moduledoc """
  A complete line sent to or received from the ADMX3652.

  For a received line, `raw` preserves exactly what the transport delivered.
  For a sent line, it is the command handed to the transport; transport-owned
  framing such as a line terminator is not included. `timestamp` is a
  monotonic native-time value recorded when the owning `ADMX3652` process
  handles the line. Received lines contain the pure protocol classification;
  sent lines have `decoded: nil`.

  `exchange_id` is present only when a line was sent for, or successfully
  claimed by, an exchange. Unsolicited and invalid received lines remain
  unlabelled.

  The timestamp is useful for ordering and elapsed-time calculations within a
  running VM. It is not a wall-clock time and is not meaningful across boots.
  """

  alias ADMX3652.{Exchange, Protocol}

  @type direction :: :sent | :received

  @enforce_keys [:direction, :raw, :timestamp, :decoded]
  defstruct [:direction, :raw, :timestamp, :decoded, :exchange_id]

  @type t :: %__MODULE__{
          direction: direction(),
          raw: binary(),
          timestamp: integer(),
          decoded: Protocol.decoded() | nil,
          exchange_id: Exchange.id() | nil
        }
end
