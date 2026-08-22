defmodule Panelmeter.MeterEvents do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def init(opts) do
    {:ok,
     %{
       pubsub: Keyword.fetch!(opts, :pubsub),
       line_topic: Keyword.fetch!(opts, :line_topic),
       reading_topic: Keyword.fetch!(opts, :reading_topic)
     }}
  end

  @impl GenServer
  def handle_info({:admx3652, _meter, {:line, %ADMX3652.Line{} = line}}, state) do
    :ok = Phoenix.PubSub.broadcast(state.pubsub, state.line_topic, line)
    {:noreply, state}
  end

  def handle_info({:admx3652, _meter, {:reading, %ADMX3652.Reading{} = reading}}, state) do
    :ok = Phoenix.PubSub.broadcast(state.pubsub, state.reading_topic, reading)
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
