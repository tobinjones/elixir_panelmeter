defmodule ADMX3652.Command do
  @moduledoc """
  Pure descriptions of individual ADMX3652 commands.

  A command describes one ordinary SCPI command and its response data. It
  does not verify the device error queue; `ADMX3652.Transaction` adds that
  common machinery around every command.

  This module is deliberately small while the command and transaction shapes
  are being reviewed. More commands are not implemented yet.
  """

  alias ADMX3652.Protocol

  @type range :: float() | :auto
  @type t :: {:get_range, Protocol.channel()} | {:set_range, Protocol.channel(), range()}

  @type response :: term()
  @type shadow_delta :: :none | {:set_range, Protocol.channel(), range()}

  @type claim_result ::
          {:claimed, response()}
          | :not_claimed
          | {:invalid, term()}

  @type finish_result ::
          {:ok, result :: term(), shadow_delta()}
          | {:error, term()}

  @ranges [0.2, 2.0, 20.0, :auto]

  @spec get_range(Protocol.channel()) :: t()
  def get_range(channel) when channel in [1, 2], do: {:get_range, channel}

  @spec set_range(Protocol.channel(), range()) :: t()
  def set_range(channel, range) when channel in [1, 2] and range in @ranges do
    {:set_range, channel, range}
  end

  @doc """
  Produces an initial response accumulator and one wire command.

  The accumulator is intentionally command-specific. A future multi-line
  response can use a map without imposing an ordered response phase.
  """
  @spec prepare(t()) :: {response(), iodata()}
  def prepare({:get_range, channel}) do
    {nil, "CONFigure:VOLTage:DC? #{channel}"}
  end

  def prepare({:set_range, channel, range}) do
    {nil, "CONFigure:VOLTage:DC #{channel},#{range}"}
  end

  @doc """
  Offers a decoded line to a command's response accumulator.

  Known asynchronous and lifecycle messages are routed outside this module.
  `:not_claimed` lets the transaction owner decide whether an interleaved
  message is harmless or evidence that protocol correlation has been lost.
  """
  @spec claim(t(), response(), Protocol.decoded()) :: claim_result()
  def claim({:get_range, channel}, nil, {:range, channel, value}) do
    # A resolved range does not reveal whether auto-ranging is enabled, so it
    # must not replace the configured range mode in the eventual shadow state.
    {:claimed, value}
  end

  def claim({:get_range, channel}, _value, {:range, channel, _duplicate}) do
    {:invalid, :duplicate_range_response}
  end

  def claim({:get_range, _channel}, _response, _decoded) do
    :not_claimed
  end

  def claim({:set_range, _channel, _range}, _response, _decoded) do
    :not_claimed
  end

  @doc """
  Validates and interprets accumulated response data at the clean error-queue
  sentinel.

  Results and shadow deltas become valid only after this function succeeds.
  """
  @spec finish(t(), response()) :: finish_result()
  def finish({:get_range, _channel}, nil), do: {:error, :missing_range_response}
  def finish({:get_range, _channel}, value), do: {:ok, {:ok, value}, :none}

  def finish({:set_range, channel, range}, nil) do
    {:ok, :ok, {:set_range, channel, range}}
  end
end
