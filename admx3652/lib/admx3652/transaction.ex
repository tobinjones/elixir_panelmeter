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

  @type primary ::
          {:awaiting, Command.state()}
          | {:done, result :: term(), Command.shadow_delta()}

  @type t :: %__MODULE__{
          command: Command.t(),
          primary: primary(),
          errors: [{integer(), binary()}]
        }

  @type step_result ::
          {:continue, t(), [iodata()]}
          | {:complete, result :: term(), Command.shadow_delta()}
          | :not_claimed
          | {:invalid, term()}

  @enforce_keys [:command, :primary]
  defstruct [:command, :primary, errors: []]

  @doc """
  Starts a transaction and returns all commands that should be written now.

  The error query is sent immediately after the primary command. This means a
  failed query that produces no primary response can still finish with the
  queued device error instead of waiting for a timeout.
  """
  @spec start(Command.t()) :: {t(), [iodata()]}
  def start(command) do
    {primary, write} =
      case Command.prepare(command) do
        {:await, command_state, write} ->
          {{:awaiting, command_state}, write}

        {:done, result, shadow_delta, write} ->
          {{:done, result, shadow_delta}, write}
      end

    {%__MODULE__{command: command, primary: primary}, [write, @error_query]}
  end

  @doc """
  Offers one decoded device line to the transaction.

  Device error entries are claimed before primary command responses. After a
  nonzero entry, another error query is requested. A zero entry is the final
  transaction sentinel: it either commits the provisional result, reports all
  drained errors, or exposes a missing primary response.
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

  def offer(%__MODULE__{primary: {:awaiting, command_state}} = transaction, decoded) do
    case Command.offer(transaction.command, command_state, decoded) do
      {:done, result, shadow_delta} ->
        transaction = %{transaction | primary: {:done, result, shadow_delta}}
        {:continue, transaction, []}

      :not_claimed ->
        :not_claimed
    end
  end

  def offer(%__MODULE__{primary: {:done, _result, _shadow_delta}}, _decoded) do
    :not_claimed
  end

  defp finish(%__MODULE__{errors: [_ | _] = errors}) do
    {:complete, {:error, {:device, Enum.reverse(errors)}}, :none}
  end

  defp finish(%__MODULE__{primary: {:done, result, shadow_delta}, errors: []}) do
    {:complete, result, shadow_delta}
  end

  defp finish(%__MODULE__{primary: {:awaiting, _command_state}, errors: []}) do
    {:invalid, :missing_primary_response}
  end
end
