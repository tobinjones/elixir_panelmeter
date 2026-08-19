defmodule ADMX3652.Exchange do
  @moduledoc """
  Pure state machine for one verified ADMX3652 command.

  An exchange consists of exactly one ordinary SCPI command followed by
  repeated `SYSTem:ERRor?` queries until the device returns `0,"No error"`.
  The error queue must be known empty before the first exchange begins.

  This module does not perform I/O, own caller references, schedule timeouts,
  or route unsolicited messages. It returns writes and results to the owning
  `ADMX3652` process.
  """

  alias ADMX3652.{Command, Protocol}

  @error_query "SYSTem:ERRor?"

  @type id :: reference()

  @type t :: %__MODULE__{
          id: id(),
          command: Command.t(),
          response: Command.response(),
          errors: [{integer(), binary()}]
        }

  @type step_result ::
          {:continue, t(), [iodata()]}
          | {:complete, result :: term(), Command.shadow_delta()}
          | :not_claimed
          | {:invalid, term()}

  @enforce_keys [:id, :command]
  defstruct [:id, :command, :response, errors: []]

  @doc """
  Starts an exchange and returns all commands that should be written now.

  The owning process supplies the inert ID used to correlate published lines;
  it has no effect on protocol matching.

  The error query is sent immediately after the primary command. This means a
  failed query that produces no primary response can still finish with the
  queued device error instead of waiting for a timeout.
  """
  @spec start(id(), Command.t()) :: {t(), [iodata()]}
  def start(exchange_id, command) when is_reference(exchange_id) do
    {response, write} = Command.prepare(command)

    {%__MODULE__{id: exchange_id, command: command, response: response}, [write, @error_query]}
  end

  @doc """
  Offers one decoded device line to the exchange.

  Device error entries are claimed before command responses. After a
  nonzero entry, another error query is requested. A zero entry is the final
  exchange sentinel: it reports drained errors or asks the command to
  validate and interpret everything it accumulated.
  """
  @spec offer(t(), Protocol.decoded()) :: step_result()
  def offer(exchange, {:error_queue, 0, _message}) do
    finish(exchange)
  end

  def offer(exchange, {:error_queue, code, message}) do
    exchange = %{
      exchange
      | errors: [{code, message} | exchange.errors]
    }

    {:continue, exchange, [@error_query]}
  end

  def offer(exchange, decoded) do
    case Command.claim(exchange.command, exchange.response, decoded) do
      {:claimed, response} ->
        exchange = %{exchange | response: response}
        {:continue, exchange, []}

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
