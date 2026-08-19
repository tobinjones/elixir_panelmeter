defmodule ADMX3652.Transaction do
  @moduledoc """
  Pure state machine for one verified ADMX3652 command.

  A transaction consists of exactly one ordinary SCPI command followed by
  repeated `SYSTem:ERRor?` queries until the device returns `0,"No error"`.
  The error queue must be known empty before the first transaction begins.

  This module does not perform I/O, own caller references, schedule timeouts,
  or route unsolicited messages. It returns writes and results to the owning
  `ADMX3652` process. Integration with that process is not implemented yet.
  """

  alias ADMX3652.{Command, Protocol}

  @error_query "SYSTem:ERRor?"

  @type t :: %__MODULE__{
          command: Command.t(),
          response: Command.response(),
          errors: [{integer(), binary()}]
        }

  @type step_result ::
          {:continue, t(), [iodata()]}
          | {:complete, result :: term(), Command.shadow_delta()}
          | :not_claimed
          | {:invalid, term()}

  @enforce_keys [:command]
  defstruct [:command, :response, errors: []]

  @doc """
  Starts a transaction and returns all commands that should be written now.

  The error query is sent immediately after the primary command. This means a
  failed query that produces no primary response can still finish with the
  queued device error instead of waiting for a timeout.
  """
  @spec start(Command.t()) :: {t(), [iodata()]}
  def start(command) do
    {response, write} = Command.prepare(command)

    {%__MODULE__{command: command, response: response}, [write, @error_query]}
  end

  @doc """
  Offers one decoded device line to the transaction.

  Device error entries are claimed before command responses. After a
  nonzero entry, another error query is requested. A zero entry is the final
  transaction sentinel: it reports drained errors or asks the command to
  validate and interpret everything it accumulated.
  """
  @spec offer(t(), Protocol.decoded()) :: step_result()
  def offer(transaction, {:error_queue, 0, _message}) do
    finish(transaction)
  end

  def offer(transaction, {:error_queue, code, message}) do
    transaction = %{
      transaction
      | errors: [{code, message} | transaction.errors]
    }

    {:continue, transaction, [@error_query]}
  end

  def offer(transaction, decoded) do
    case Command.claim(transaction.command, transaction.response, decoded) do
      {:claimed, response} ->
        transaction = %{transaction | response: response}
        {:continue, transaction, []}

      :not_claimed ->
        :not_claimed

      {:invalid, reason} ->
        {:invalid, {:command_response, reason}}
    end
  end

  defp finish(%__MODULE__{errors: [_ | _] = errors}) do
    {:complete, {:error, {:device, Enum.reverse(errors)}}, :none}
  end

  defp finish(%__MODULE__{command: command, response: response, errors: []}) do
    case Command.finish(command, response) do
      {:ok, result, shadow_delta} -> {:complete, result, shadow_delta}
      {:error, reason} -> {:invalid, reason}
    end
  end
end
