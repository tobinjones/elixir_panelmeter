defmodule ADMX3652.LinePublisher do
  @moduledoc """
  Publication boundary for the ordered ADMX3652 line stream.

  A publisher runs synchronously in the owning `ADMX3652` process, so calls
  should return quickly. The firmware can implement this callback with
  Phoenix PubSub without making Phoenix a dependency of the pure driver.
  """

  alias ADMX3652.Line

  @callback publish(Line.t(), publisher_opts :: term()) :: :ok
end
