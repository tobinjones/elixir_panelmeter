defmodule ADMX3652.Command do
  @moduledoc """
  Pure descriptions of individual ADMX3652 commands.

  A command describes one ordinary SCPI command and its response data. It
  does not verify the device error queue; `ADMX3652.Exchange` adds that
  common machinery around every command.

  Commands also describe the shadow-state change that becomes valid after a
  verified exchange succeeds.
  """

  alias ADMX3652.Protocol

  @type range :: float() | :auto
  @type nplc :: float()
  @type line_frequency :: 50 | 60
  @type read_mode :: :single | :continuous
  @type trigger_source :: :internal | :external
  @type t ::
          {:get_range, Protocol.channel()}
          | {:set_range, Protocol.channel(), range()}
          | {:get_nplc, Protocol.channel()}
          | {:set_nplc, Protocol.channel(), nplc()}
          | {:set_line_frequency, line_frequency()}
          | {:set_read_mode, Protocol.channel(), read_mode()}
          | :get_trigger_source
          | {:set_trigger_source, trigger_source()}

  @type response :: term()
  @type shadow_delta ::
          :none
          | {:set_range, Protocol.channel(), range()}
          | {:set_nplc, Protocol.channel(), nplc()}
          | {:set_line_frequency, line_frequency()}
          | {:set_read_mode, Protocol.channel(), read_mode()}
          | {:set_trigger_source, trigger_source()}

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

  @spec get_nplc(Protocol.channel()) :: t()
  def get_nplc(channel) when channel in [1, 2], do: {:get_nplc, channel}

  @spec set_nplc(Protocol.channel(), number()) :: t()
  def set_nplc(channel, nplc) when channel in [1, 2] do
    if valid_nplc?(nplc),
      do: {:set_nplc, channel, nplc * 1.0},
      else: raise(ArgumentError, "invalid NPLC: #{inspect(nplc)}")
  end

  @spec set_line_frequency(line_frequency()) :: t()
  def set_line_frequency(frequency) when frequency in [50, 60],
    do: {:set_line_frequency, frequency}

  @spec set_read_mode(Protocol.channel(), read_mode()) :: t()
  def set_read_mode(channel, mode)
      when channel in [1, 2] and mode in [:single, :continuous],
      do: {:set_read_mode, channel, mode}

  @spec get_trigger_source() :: t()
  def get_trigger_source, do: :get_trigger_source

  @spec set_trigger_source(trigger_source()) :: t()
  def set_trigger_source(source) when source in [:internal, :external],
    do: {:set_trigger_source, source}

  @spec valid_range?(term()) :: boolean()
  def valid_range?(range), do: range in @ranges

  @spec valid_nplc?(term()) :: boolean()
  def valid_nplc?(nplc) when is_number(nplc) and nplc >= 1, do: true
  def valid_nplc?(nplc), do: nplc in [0.05, 0.1, 0.25, 0.5]

  @spec valid_line_frequency?(term()) :: boolean()
  def valid_line_frequency?(frequency), do: frequency in [50, 60]

  @spec valid_read_mode?(term()) :: boolean()
  def valid_read_mode?(mode), do: mode in [:single, :continuous]

  @spec valid_trigger_source?(term()) :: boolean()
  def valid_trigger_source?(source), do: source in [:internal, :external]

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

  def prepare({:get_nplc, channel}) do
    {nil, "CONFigure:VOLTage:DC:NPLCycles? #{channel}"}
  end

  def prepare({:set_nplc, channel, nplc}) do
    {nil, "CONFigure:VOLTage:DC:NPLCycles #{channel},#{nplc}"}
  end

  def prepare({:set_line_frequency, frequency}), do: {nil, "SYSTem:PLC:SET #{frequency}"}

  def prepare({:set_read_mode, channel, mode}) do
    value = if mode == :continuous, do: "ON", else: "OFF"
    {nil, "CONFigure:CONTINUOUS:READ #{channel},#{value}"}
  end

  def prepare(:get_trigger_source), do: {nil, "TRIGger:SOURce?"}

  def prepare({:set_trigger_source, source}) do
    value = if source == :internal, do: "INTernal", else: "EXTernal"
    {nil, "TRIGger:SOURce #{value}"}
  end

  @doc """
  Offers a decoded line to a command's response accumulator.

  Known asynchronous and lifecycle messages are routed outside this module.
  `:not_claimed` lets the exchange owner decide whether an interleaved
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

  def claim({:get_nplc, channel}, nil, {:nplc, channel, value}), do: {:claimed, value}

  def claim({:get_nplc, channel}, _value, {:nplc, channel, _duplicate}),
    do: {:invalid, :duplicate_nplc_response}

  def claim({:get_nplc, _channel}, _response, _decoded), do: :not_claimed

  def claim(:get_trigger_source, nil, {:trigger_source, source}), do: {:claimed, source}

  def claim(:get_trigger_source, _source, {:trigger_source, _duplicate}),
    do: {:invalid, :duplicate_trigger_source_response}

  def claim(:get_trigger_source, _response, _decoded), do: :not_claimed
  def claim({:set_nplc, _channel, _nplc}, _response, _decoded), do: :not_claimed
  def claim({:set_line_frequency, _frequency}, _response, _decoded), do: :not_claimed
  def claim({:set_read_mode, _channel, _mode}, _response, _decoded), do: :not_claimed
  def claim({:set_trigger_source, _source}, _response, _decoded), do: :not_claimed

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

  def finish({:get_nplc, _channel}, nil), do: {:error, :missing_nplc_response}

  def finish({:get_nplc, channel}, value),
    do: {:ok, {:ok, value}, {:set_nplc, channel, value}}

  def finish({:set_nplc, channel, nplc}, nil),
    do: {:ok, :ok, {:set_nplc, channel, nplc}}

  def finish({:set_line_frequency, frequency}, nil),
    do: {:ok, :ok, {:set_line_frequency, frequency}}

  def finish({:set_read_mode, channel, mode}, nil),
    do: {:ok, :ok, {:set_read_mode, channel, mode}}

  def finish(:get_trigger_source, nil), do: {:error, :missing_trigger_source_response}

  def finish(:get_trigger_source, source),
    do: {:ok, {:ok, source}, {:set_trigger_source, source}}

  def finish({:set_trigger_source, source}, nil),
    do: {:ok, :ok, {:set_trigger_source, source}}
end
