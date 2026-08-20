defmodule Panelmeter.Distribution do
  @moduledoc """
  Brings up Erlang distribution, then starts libcluster.

  Nerves does not start distribution for us, and the name we want depends on
  runtime state: the device names itself after its own `eth0` address, which is
  not known at boot — `vintage_net` has to bring the interface up and get a DHCP
  lease first. On an RPi3 that ethernet is USB-attached and enumerates slowly,
  and "slowly" is not a fixed number, so this does not wait with a timeout. It
  subscribes to the address property and reacts whenever the address turns up,
  a minute or an hour later.

  Until then the device runs standalone, which still leaves SSH and OTA updates
  working, because `shoehorn` starts `nerves_pack` before this application.

  libcluster cannot connect to anything before the node has a name, so its
  supervisor is started from here into `Panelmeter.ClusterSupervisor` rather
  than from the application supervisor.
  """

  use GenServer

  require Logger

  # vintage_net is a target-only dependency, pulled in by nerves_pack, and this
  # process only runs on target. The module still compiles on the host so that
  # `ipv4/1` stays testable there.
  @compile {:no_warn_undefined, VintageNet}

  @interface "eth0"
  @property ["interface", @interface, "addresses"]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The node name this device uses, or nil if distribution never started."
  def node_name do
    case node() do
      :nonode@nohost -> nil
      name -> name
    end
  end

  @doc "The cluster cookie. Every node in the cluster must agree on it."
  def default_cookie do
    Application.get_env(:panelmeter, :cluster_cookie, :panelmeter_cookie)
  end

  @doc """
  The routable IPv4 address from a VintageNet addresses list, as a string.

  Returns `:error` if there isn't one yet.
  """
  def ipv4(addresses) when is_list(addresses) do
    addresses
    |> Enum.find(&match?(%{family: :inet, scope: :universe}, &1))
    |> case do
      %{address: address} -> {:ok, address |> :inet.ntoa() |> to_string()}
      nil -> :error
    end
  end

  def ipv4(_), do: :error

  @impl true
  def init(opts) do
    VintageNet.subscribe(@property)

    state = %{
      name: Keyword.get(opts, :name_prefix, "panelmeter"),
      cookie: Keyword.get(opts, :cookie, default_cookie()),
      started: false
    }

    # The address may already be there — subscribing only reports *changes*.
    {:ok, state, {:continue, :check_existing}}
  end

  @impl true
  def handle_continue(:check_existing, state) do
    {:noreply, maybe_start(state, VintageNet.get(@property, []))}
  end

  @impl true
  def handle_info({VintageNet, @property, _old, new, _meta}, state) do
    {:noreply, maybe_start(state, new)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Distribution can only be started once. A later address change would leave
  # the node name stale, which is worth knowing about but not worth a reboot.
  defp maybe_start(%{started: true} = state, _addresses), do: state

  defp maybe_start(state, addresses) do
    case ipv4(addresses) do
      {:ok, ip} -> start_distribution(state, ip)
      :error -> state
    end
  end

  defp start_distribution(state, ip) do
    with :ok <- ensure_epmd(),
         {:ok, _pid} <- Node.start(:"#{state.name}@#{ip}", :longnames) do
      Node.set_cookie(state.cookie)
      Logger.info("distribution: started as #{node()}")
      start_libcluster()
      %{state | started: true}
    else
      error ->
        Logger.warning(
          "distribution: could not start on #{ip} (#{inspect(error)}); " <>
            "will retry when the address changes"
        )

        state
    end
  end

  defp start_libcluster do
    case Application.get_env(:libcluster, :topologies) do
      topologies when is_list(topologies) ->
        spec = {Cluster.Supervisor, [topologies, [name: Panelmeter.LibclusterSupervisor]]}

        case DynamicSupervisor.start_child(Panelmeter.ClusterSupervisor, spec) do
          {:ok, _pid} -> :ok
          {:error, reason} -> Logger.error("cluster: libcluster failed: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  end

  # net_kernel normally starts epmd itself, but it is not always on the PATH
  # that erl inherits on Nerves, so start it explicitly.
  defp ensure_epmd do
    case System.cmd("epmd", ["-daemon"], stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, code} -> {:error, {:epmd_failed, code, String.trim(out)}}
    end
  rescue
    e in ErlangError -> {:error, {:epmd_missing, e}}
  end
end
