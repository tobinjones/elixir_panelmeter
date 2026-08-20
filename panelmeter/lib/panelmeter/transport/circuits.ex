defmodule Panelmeter.Transport.Circuits do
  @moduledoc """
  ADMX3652 transport for the panelmeter's Raspberry Pi 3 hardware.

  The UART is the PL011 exposed as `ttyAMA0`. The transport owns the port and
  delivers complete CRLF-delimited lines to `ADMX3652`.

  The module enable line is GPIO23. It always remains an input: removing the
  pull-down enables the module through its own pull-up, while applying the
  pull-down disables it. The pin must never be driven as an output since the
  module's pull-up may be referenced to 5 V.
  """

  use GenServer

  @behaviour ADMX3652.Transport

  defstruct [:owner, :uart_mod, :uart, :port, :gpio_mod, :en]

  @type state :: %__MODULE__{
          owner: pid(),
          uart_mod: module(),
          uart: pid(),
          port: binary(),
          gpio_mod: module(),
          en: term()
        }

  @impl ADMX3652.Transport
  def start_link(owner, opts) do
    GenServer.start_link(__MODULE__, {owner, opts})
  end

  @impl ADMX3652.Transport
  def write(transport, line) do
    GenServer.call(transport, {:write, line})
  end

  @impl ADMX3652.Transport
  def set_enabled(transport, enabled) when is_boolean(enabled) do
    GenServer.call(transport, {:set_enabled, enabled})
  end

  @impl ADMX3652.Transport
  def enabled?(transport) do
    GenServer.call(transport, :enabled?)
  end

  @impl GenServer
  def init({owner, opts}) do
    port = Keyword.fetch!(opts, :port)
    speed = Keyword.get(opts, :speed, 460_800)
    en_gpio = Keyword.fetch!(opts, :en_gpio)
    uart_mod = Keyword.get(opts, :uart_module, Circuits.UART)
    gpio_mod = Keyword.get(opts, :gpio_module, Circuits.GPIO)

    case gpio_mod.open(en_gpio, :input, pull_mode: :none) do
      {:ok, en} ->
        open_with_gpio(owner, uart_mod, gpio_mod, en, port, speed)

      {:error, reason} ->
        {:stop, {:gpio_open_failed, en_gpio, reason}}
    end
  end

  @impl GenServer
  def handle_call({:write, line}, _from, state) do
    # Circuits.UART.Framing.Line appends the configured CRLF separator.
    result = state.uart_mod.write(state.uart, IO.iodata_to_binary(line))
    {:reply, result, state}
  end

  def handle_call({:set_enabled, enabled}, _from, state) do
    pull_mode = if enabled, do: :none, else: :pulldown
    result = state.gpio_mod.set_pull_mode(state.en, pull_mode)
    {:reply, result, state}
  end

  def handle_call(:enabled?, _from, state) do
    result =
      case state.gpio_mod.read(state.en) do
        1 -> {:ok, true}
        0 -> {:ok, false}
        other -> {:error, {:unexpected_gpio_value, other}}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_info({:circuits_uart, port, {:error, reason}}, %{port: port} = state) do
    notify_owner(state, {:error, reason})
    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, {:partial, line}}, %{port: port} = state) do
    notify_owner(state, {:error, {:partial_line, line}})
    {:noreply, state}
  end

  def handle_info({:circuits_uart, port, line}, %{port: port} = state)
      when is_binary(line) do
    case String.replace(line, <<0>>, "") do
      "" -> :ok
      clean_line -> notify_owner(state, {:line, clean_line})
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state) do
    state.uart_mod.close(state.uart)
    state.gpio_mod.close(state.en)
    :ok
  end

  defp open_with_gpio(owner, uart_mod, gpio_mod, en, port, speed) do
    case open_uart(uart_mod, port, speed) do
      {:ok, uart} ->
        {:ok,
         %__MODULE__{
           owner: owner,
           uart_mod: uart_mod,
           uart: uart,
           port: port,
           gpio_mod: gpio_mod,
           en: en
         }}

      {:error, reason} ->
        gpio_mod.close(en)
        {:stop, {:uart_open_failed, port, reason}}
    end
  end

  defp open_uart(uart_mod, port, speed) do
    with {:ok, uart} <- uart_mod.start_link(),
         :ok <- uart_mod.open(uart, port, uart_options(speed)) do
      {:ok, uart}
    end
  end

  defp uart_options(speed) do
    [
      speed: speed,
      data_bits: 8,
      stop_bits: 1,
      parity: :none,
      flow_control: :none,
      active: true,
      framing: {Circuits.UART.Framing.Line, separator: "\r\n"}
    ]
  end

  defp notify_owner(state, event) do
    send(state.owner, {:admx3652_transport, self(), event})
  end
end
