defmodule ADMX3652.Command do
  @moduledoc """
  Pure descriptions of individual ADMX3652 commands.

  A command describes one ordinary SCPI command and its primary response. It
  does not verify the device error queue; `ADMX3652.Transaction` adds that
  common machinery around every command.

  This module is deliberately small while the command and transaction shapes
  are being reviewed. More commands are not implemented yet.
  """

  alias ADMX3652.Protocol

  @type range :: float() | :auto
  @type t :: {:get_range, Protocol.channel()} | {:set_range, Protocol.channel(), range()}

  @type state :: {:await_range, Protocol.channel()}
  @type shadow_delta :: :none | {:set_range, Protocol.channel(), range()}

  @type prepare_result ::
          {:await, state(), iodata()}
          | {:done, result :: term(), shadow_delta(), iodata()}

  @type offer_result ::
          {:done, result :: term(), shadow_delta()}
          | :not_claimed

  @ranges [0.2, 2.0, 20.0, :auto]

  @spec get_range(Protocol.channel()) :: t()
  def get_range(channel) when channel in [1, 2], do: {:get_range, channel}

  @spec set_range(Protocol.channel(), range()) :: t()
  def set_range(channel, range) when channel in [1, 2] and range in @ranges do
    {:set_range, channel, range}
  end

  @doc """
  Produces the command state and single wire command for a transaction.

  `:done` means that the device command is silent, not that the transaction has
  succeeded. The result and shadow delta remain provisional until the shared
  error-queue check succeeds.
  """
  @spec prepare(t()) :: prepare_result()
  def prepare({:get_range, channel}) do
    {:await, {:await_range, channel}, ["CONFigure:VOLTage:DC? ", Integer.to_string(channel)]}
  end

  def prepare({:set_range, channel, range}) do
    write = [
      "CONFigure:VOLTage:DC ",
      Integer.to_string(channel),
      ?,,
      format_range(range)
    ]

    {:done, :ok, {:set_range, channel, range}, write}
  end

  @doc """
  Offers a decoded line to a command awaiting its primary response.

  Known asynchronous and lifecycle messages are routed outside this module.
  `:not_claimed` lets the transaction owner decide whether an interleaved
  message is harmless or evidence that protocol correlation has been lost.
  """
  @spec offer(t(), state(), Protocol.decoded()) :: offer_result()
  def offer(
        {:get_range, channel},
        {:await_range, channel},
        {:range, channel, value}
      ) do
    # A resolved range does not reveal whether auto-ranging is enabled, so it
    # must not replace the configured range mode in the eventual shadow state.
    {:done, {:ok, value}, :none}
  end

  def offer({:get_range, channel}, {:await_range, channel}, _decoded) do
    :not_claimed
  end

  defp format_range(:auto), do: "AUTO"
  defp format_range(range), do: Float.to_string(range)
end
