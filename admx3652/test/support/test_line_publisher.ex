defmodule ADMX3652.TestLinePublisher do
  @moduledoc false

  @behaviour ADMX3652.LinePublisher

  @impl ADMX3652.LinePublisher
  def publish(line, test) do
    send(test, {:published_line, line})
    :ok
  end
end
