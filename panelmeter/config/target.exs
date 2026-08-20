import Config

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

# The RPi3 has no real-time clock. Use the same on-site NTP servers as the
# proven firmware and briefly wait for nerves_time to establish a valid clock.
config :nerves_time,
  servers: ["172.20.0.30", "172.20.0.31"],
  await_initialization_timeout: :timer.seconds(5)

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

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
