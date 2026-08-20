defmodule Panelmeter.Transport.CircuitsTest do
  use ExUnit.Case, async: true

  alias Panelmeter.Transport.Circuits

  defmodule UART do
    use Agent

    def start_link do
      Agent.start_link(fn -> %{open: nil, writes: [], closed?: false} end)
    end

    def open(uart, port, opts) do
      Agent.update(uart, &%{&1 | open: {port, opts}})
    end

    def write(uart, data) do
      Agent.update(uart, &%{&1 | writes: &1.writes ++ [IO.iodata_to_binary(data)]})
    end

    def close(uart) do
      Agent.update(uart, &%{&1 | closed?: true})
    end

    def state(uart), do: Agent.get(uart, & &1)
  end

  defmodule GPIO do
    use Agent

    def open(spec, direction, opts) do
      Agent.start_link(fn ->
        %{spec: spec, direction: direction, pull_mode: opts[:pull_mode], closed?: false}
      end)
    end

    def set_pull_mode(gpio, pull_mode) do
      Agent.update(gpio, &%{&1 | pull_mode: pull_mode})
    end

    def read(gpio) do
      Agent.get(gpio, fn
        %{pull_mode: :none} -> 1
        %{pull_mode: :pulldown} -> 0
      end)
    end

    def close(gpio) do
      Agent.update(gpio, &%{&1 | closed?: true})
    end

    def state(gpio), do: Agent.get(gpio, & &1)
  end

  setup do
    {:ok, transport} =
      Circuits.start_link(self(),
        port: "ttyAMA0",
        speed: 460_800,
        en_gpio: "GPIO23",
        uart_module: UART,
        gpio_module: GPIO
      )

    state = :sys.get_state(transport)

    on_exit(fn ->
      if Process.alive?(transport), do: GenServer.stop(transport)
      if Process.alive?(state.uart), do: Agent.stop(state.uart)
      if Process.alive?(state.en), do: Agent.stop(state.en)
    end)

    %{transport: transport, state: state}
  end

  test "opens the proven UART and EN configuration", %{state: state} do
    assert %{spec: "GPIO23", direction: :input, pull_mode: :none} = GPIO.state(state.en)

    assert %{open: {"ttyAMA0", uart_opts}} = UART.state(state.uart)
    assert uart_opts[:speed] == 460_800
    assert uart_opts[:data_bits] == 8
    assert uart_opts[:stop_bits] == 1
    assert uart_opts[:parity] == :none
    assert uart_opts[:flow_control] == :none
    assert uart_opts[:active]
    assert uart_opts[:framing] == {Elixir.Circuits.UART.Framing.Line, separator: "\r\n"}
  end

  test "leaves CRLF termination to the configured UART framer", %{
    transport: transport,
    state: state
  } do
    assert :ok = Circuits.write(transport, "*IDN?")
    assert UART.state(state.uart).writes == ["*IDN?"]

    {:ok, framing} = Elixir.Circuits.UART.Framing.Line.init(separator: "\r\n")

    assert {:ok, "*IDN?\r\n", _framing} =
             Elixir.Circuits.UART.Framing.Line.add_framing("*IDN?", framing)
  end

  test "controls EN using input pull mode only", %{transport: transport, state: state} do
    assert {:ok, true} = Circuits.enabled?(transport)

    assert :ok = Circuits.set_enabled(transport, false)
    assert {:ok, false} = Circuits.enabled?(transport)
    assert GPIO.state(state.en).direction == :input
    assert GPIO.state(state.en).pull_mode == :pulldown

    assert :ok = Circuits.set_enabled(transport, true)
    assert {:ok, true} = Circuits.enabled?(transport)
    assert GPIO.state(state.en).direction == :input
    assert GPIO.state(state.en).pull_mode == :none
  end

  test "forwards UART lines and errors while removing power-on NUL bytes", %{
    transport: transport
  } do
    send(transport, {:circuits_uart, "ttyAMA0", <<0, 0, "DAQ is ready to use">>})

    assert_receive {:admx3652_transport, ^transport, {:line, "DAQ is ready to use"}}

    send(transport, {:circuits_uart, "ttyAMA0", <<0, 0>>})
    refute_receive {:admx3652_transport, ^transport, {:line, _line}}

    send(transport, {:circuits_uart, "ttyAMA0", {:error, :eio}})
    assert_receive {:admx3652_transport, ^transport, {:error, :eio}}

    send(transport, {:circuits_uart, "ttyAMA0", {:partial, "incomplete"}})

    assert_receive {:admx3652_transport, ^transport, {:error, {:partial_line, "incomplete"}}}
  end
end
