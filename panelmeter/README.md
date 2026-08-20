# Panelmeter

Nerves firmware for the Raspberry Pi 3-based ADMX3652 panelmeter.

## Hardware

The firmware uses the following Raspberry Pi GPIO-header signals:

| Function | BCM GPIO | Header pin | Linux interface |
|---|---:|---:|---|
| ADMX3652 UART TX | GPIO14 | 8 | `/dev/ttyAMA0` |
| ADMX3652 UART RX | GPIO15 | 10 | `/dev/ttyAMA0` |
| ADMX3652 CTRL | GPIO18 | 12 | `/sys/class/pwm/pwmchip0` |
| ADMX3652 EN | GPIO23 | 16 | `GPIO23` |

The UART runs at 460,800 baud. EN is controlled only through the GPIO input
pull mode: no pull enables the module and pull-down disables it. Never configure
GPIO23 as an output because the module's pull-up may be referenced to 5 V.

GPIO18 is reserved for hardware PWM but the firmware does not currently drive
CTRL.

The RPi3 boot partition is customized to keep the kernel console off the meter's
UART and to make PWM0 available on GPIO18. See
[`RPI3_BOOT_CUSTOMIZATION.md`](RPI3_BOOT_CUSTOMIZATION.md).

## Networking and time

The target uses DHCP on wired `eth0`. `usb0` remains enabled as a direct-connect
recovery interface, and Wi-Fi is not configured. The RPi3 has no real-time
clock, so `nerves_time` synchronizes at boot. On a network with no route to the
internet, name the site's own servers in `config/site.exs` — see
[`config/site.exs.example`](config/site.exs.example).

## Targets

Nerves applications produce images for hardware targets based on the
`MIX_TARGET` environment variable. If `MIX_TARGET` is unset, `mix` builds an
image that runs on the host (e.g., your laptop). This is useful for executing
logic tests, running utilities, and debugging. Other targets are represented by
a short name like `rpi5` that maps to a Nerves system image for that platform.
All of this logic is in the generated `mix.exs` and may be customized. For more
information about targets see:

https://nerves.hexdocs.pm/supported-targets.html

## Getting Started

To start your Nerves app:
  * `export MIX_TARGET=my_target` or prefix every command with
    `MIX_TARGET=my_target`. For example, `MIX_TARGET=rpi5`
  * Install dependencies with `mix deps.get`
  * Create firmware with `mix firmware`
  * Burn to an SD card with `mix burn`

## Learn more

  * Official docs: https://nerves.hexdocs.pm/getting-started.html
  * Official website: https://nerves-project.org/
  * Forum: https://elixirforum.com/c/nerves-forum
  * Elixir Discord #nerves channel: https://discord.gg/elixir
  * Source: https://github.com/nerves-project/nerves
