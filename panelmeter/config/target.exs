import Config

# Site-local values that must not be committed: the cluster cookie, the gossip
# secret, and the NTP servers of an isolated network. `config/site.exs` is
# git-ignored and evaluates to a keyword list; see config/site.exs.example.
# Environment variables win over it, which is what CI would use.
site =
  if File.exists?("config/site.exs") do
    {values, _bindings} = Code.eval_file("config/site.exs")
    values
  else
    []
  end

site_value = fn key, var -> System.get_env(var) || site[key] end

if Mix.target() == :rpi3 do
  # MAINTENANCE: config/fwup.conf is a copy of the system's generated file and
  # does not track it. After bumping nerves_system_rpi3, regenerate and re-apply
  # the PANELMETER changes:
  #
  #   MIX_TARGET=rpi3 mix nerves.artifact.details nerves_system_rpi3 --copy-fwup-conf /tmp/new.conf
  #   diff /tmp/new.conf config/fwup.conf
  #
  # Also diff config/boot/* against deps/nerves_system_rpi3/.
  config :nerves, :firmware, fwup_conf: "config/fwup.conf"

  config :panelmeter, :admx3652,
    name: Panelmeter.Meter,
    transport: Panelmeter.Transport.Circuits,
    transport_opts: [port: "ttyAMA0", speed: 460_800, en_gpio: "GPIO23"],
    pubsub: Panelmeter.PubSub
end

# Use Ringlogger as the logger backend and remove :console.
# See https://ring-logger.hexdocs.pm/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# The RPi3 has no real-time clock, so briefly wait for nerves_time to establish
# one. A site on an isolated network has to name its own servers — set
# PANELMETER_NTP_SERVERS (comma separated) or `:ntp_servers` in config/site.exs.
# With neither, nerves_time uses its public pool default, which is right for a
# board with a route to the internet and useless for one without.
config :nerves_time, await_initialization_timeout: :timer.seconds(5)

case site_value.(:ntp_servers, "PANELMETER_NTP_SERVERS") do
  nil ->
    :ok

  servers when is_list(servers) ->
    config :nerves_time, servers: servers

  list ->
    config :nerves_time, servers: String.split(list, ",", trim: true) |> Enum.map(&String.trim/1)
end

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://nerves-ssh.hexdocs.pm/readme.html for general SSH configuration
# * See https://ssh-subsystem-fwup.hexdocs.pm/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Configure the network using vintage_net
#
# This appliance uses wired Ethernet. usb0 remains available as a direct-connect
# recovery path; Wi-Fi is deliberately not configured.
#
# See https://github.com/nerves-networking/vintage_net for more information
config :vintage_net,
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }}
  ]

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    }
  ]

# Erlang distribution and clustering
#
# The node name is not set here — the device names itself `panelmeter@<eth0 ip>`
# at runtime, once vintage_net has a DHCP lease. See Panelmeter.Distribution.
#
# The cookie and the gossip secret together are what let a node join this
# cluster, and joining the cluster is remote code execution on the board, so
# neither is committed. Supply both per build, from the environment or from
# config/site.exs. A target build refuses to produce firmware without them, in
# the same spirit as the SSH key check above: firmware anyone can join is worse
# than a build that fails.
required = fn key, var ->
  site_value.(key, var) ||
    Mix.raise("""
    #{var} is not set and config/site.exs does not supply :#{key}.

    The cluster cookie and the gossip secret decide who may join this board's
    Erlang cluster, so they are not in the repository. Export both, or copy
    config/site.exs.example to config/site.exs and fill it in.
    """)
end

cluster_cookie = required.(:cluster_cookie, "PANELMETER_CLUSTER_COOKIE")
gossip_secret = required.(:gossip_secret, "PANELMETER_GOSSIP_SECRET")

config :panelmeter, cluster_cookie: String.to_atom(to_string(cluster_cookie))

# Cluster.Strategy.Gossip discovers peers over multicast UDP, so no node has to
# know any other's address — which matters because every end of this is on a
# DHCP lease. `secret` encrypts the gossip and keeps this cluster distinct from
# anything else on the default multicast group, including the nerves_joiner
# prototype. The Erlang cookie is still what ultimately gates a connection;
# this just stops the connection being attempted.
config :libcluster,
  topologies: [
    panelmeter: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_addr: "233.252.1.32",
        # keep packets on the local network
        multicast_ttl: 1,
        secret: gossip_secret
      ]
    ]
  ]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
