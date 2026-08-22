defmodule ADMX3652.TestTransport do
  @moduledoc false

  use GenServer

  @behaviour ADMX3652.Transport

  defstruct [:owner, :test, :write_error, enabled: false]

  @impl ADMX3652.Transport
  def start_link(owner, opts) do
    GenServer.start_link(__MODULE__, {owner, opts})
  end

  @impl ADMX3652.Transport
  def write(transport, line) do
    GenServer.call(transport, {:write, line})
  end

  @impl ADMX3652.Transport
  def set_enabled(transport, enabled) do
    GenServer.call(transport, {:set_enabled, enabled})
  end

  @impl ADMX3652.Transport
  def enabled?(transport) do
    GenServer.call(transport, :enabled?)
  end

  # Test-only API

  def send_line(transport, line) do
    GenServer.cast(transport, {:send_line, line})
  end

  def send_error(transport, reason) do
    GenServer.cast(transport, {:send_error, reason})
  end

  @impl GenServer
  def init({owner, opts}) do
    {:ok,
     %__MODULE__{
       owner: owner,
       test: Keyword.fetch!(opts, :test),
       write_error: Keyword.get(opts, :write_error),
       enabled: Keyword.get(opts, :enabled, false)
     }}
  end

  @impl GenServer
  def handle_call({:write, _line}, _from, %{write_error: reason} = state)
      when not is_nil(reason) do
    {:reply, {:error, reason}, state}
  end

  def handle_call({:write, line}, _from, state) do
    send(state.test, {:transport_write, line})
    {:reply, :ok, state}
  end

  def handle_call({:set_enabled, enabled}, _from, state) do
    send(state.test, {:transport_enabled, enabled})
    {:reply, :ok, %{state | enabled: enabled}}
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, {:ok, state.enabled}, state}
  end

  @impl GenServer
  def handle_cast({:send_line, line}, state) do
    send(
      state.owner,
      {:admx3652_transport, self(), {:line, line}}
    )

    {:noreply, state}
  end

  def handle_cast({:send_error, reason}, state) do
    send(
      state.owner,
      {:admx3652_transport, self(), {:error, reason}}
    )

    {:noreply, state}
  end
end
