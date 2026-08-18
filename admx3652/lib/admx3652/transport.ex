defmodule ADMX3652.Transport do
  @moduledoc """
  Transport interface for an ADMX3652.

  Incoming complete lines are sent to the owner as:

      {:admx3652_transport, transport, {:line, line}}

  Transport errors are sent as:

      {:admx3652_transport, transport, {:error, reason}}
  """

  @type t :: pid()
  @type reason :: term()

  @callback start_link(owner :: pid(), opts :: keyword()) ::
              GenServer.on_start()

  @callback write(t(), iodata()) ::
              :ok | {:error, reason()}

  @callback set_enabled(t(), boolean()) ::
              :ok | {:error, reason()}

  @callback enabled?(t()) ::
              {:ok, boolean()} | {:error, reason()}
end
