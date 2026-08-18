defmodule ADMX3652 do
  @moduledoc """
  Main process for an ADMX3652 panel meter.

  The process owns the transport and will eventually coordinate the meter's
  startup, configuration, and shadow state.
  """

  @behaviour :gen_statem

  @type state :: :off | :starting | :configuring | :ready | :desynchronised

  defmodule Data do
    @moduledoc false

    @enforce_keys [:transport_mod, :transport]
    defstruct [:transport_mod, :transport]

    @type t :: %__MODULE__{
            transport_mod: module(),
            transport: ADMX3652.Transport.t()
          }
  end

  @doc """
  Starts the ADMX3652 process and its transport.

  Options:

    * `:transport` - transport module (required)
    * `:transport_opts` - options passed to the transport (defaults to `[]`)
    * `:name` - optional `:gen_statem` registration name
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) do
    case Keyword.get(opts, :name) do
      nil -> :gen_statem.start_link(__MODULE__, opts, [])
      name -> :gen_statem.start_link(server_name(name), __MODULE__, opts, [])
    end
  end

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @impl :gen_statem
  def callback_mode, do: :handle_event_function

  @impl :gen_statem
  def init(opts) do
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    {:ok, transport} = transport_mod.start_link(self(), transport_opts)

    state =
      case transport_mod.enabled?(transport) do
        {:ok, false} -> :off
        {:ok, true} -> :desynchronised
        {:error, _reason} -> :desynchronised
      end

    {:ok, state, %Data{transport_mod: transport_mod, transport: transport}}
  end

  @impl :gen_statem
  def handle_event(_event_type, _event_content, _state, _data) do
    :keep_state_and_data
  end

  defp server_name(name) when is_atom(name), do: {:local, name}
  defp server_name({:global, _term} = name), do: name
  defp server_name({:via, _module, _term} = name), do: name
end
