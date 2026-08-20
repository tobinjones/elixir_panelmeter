# Raspberry Pi 3 boot partition setup

The panelmeter firmware owns selected Raspberry Pi 3 boot-partition files so
that:

- the Linux kernel does not use the ADMX3652 UART;
- onboard audio does not claim PWM0; and
- hardware PWM0 is available on GPIO18.

These changes are specific to `nerves_system_rpi3` 2.1.1.

## Implementation

The stock boot files were copied from `deps/nerves_system_rpi3/` to
`config/boot/`:

- `cmdline-a.txt`
- `cmdline-b.txt`
- `config.txt`

In both command-line files, `console=serial0,115200` was removed. The
`miniuart-bt` overlay maps the GPIO UART to the PL011 at `/dev/ttyAMA0`, so
removing the console prevents kernel output from being transmitted to the
ADMX3652 before the Elixir application starts.

In `config/boot/config.txt`, onboard audio was disabled:

```text
dtparam=audio=off
```

The PWM overlay was then enabled:

```text
dtoverlay=pwm,pin=18,func=2
```

`func=2` selects ALT5 for GPIO18.

## Custom fwup configuration

The generated `fwup.conf` from the locked RPi 3 system artifact was copied to
`config/fwup.conf`:

```sh
MIX_TARGET=rpi3 mix nerves.artifact.details nerves_system_rpi3 \
  --copy-fwup-conf config/fwup.conf
```

Its `cmdline-a.txt`, `cmdline-b.txt`, and `config.txt` resources were
redirected to `config/boot/` using `${MIX_BUILD_PATH}/../../`.

`overlays/pwm.dtbo` was declared as a resource and written by all five tasks
that populate an RPi 3 boot partition:

- `complete`
- `upgrade.old-a`
- `upgrade.old-b`
- `upgrade.a`
- `upgrade.b`

There must be one PWM resource declaration and five PWM resource handlers:

```sh
rg -c '^file-resource overlays/pwm\.dtbo' config/fwup.conf
rg -c '^\s+on-resource overlays/pwm\.dtbo' config/fwup.conf
```

The expected results are `1` and `5`.

The custom layout is guarded in `config/target.exs`:

```elixir
if Mix.target() == :rpi3 do
  config :nerves, :firmware, fwup_conf: "config/fwup.conf"
end
```

The guard is required because this project supports hardware targets other
than the Raspberry Pi 3.

## Development-shell dependencies

`pkg-config` and `libmnl` were added to the repository's Nix development
shell. They are required to compile `vintage_net_wifi` for the target and
`nerves_uevent` for host tests.

Enter the development shell before running the commands below:

```sh
nix develop
```

## Build and test

```sh
cd panelmeter
mix format --check-formatted
mix test
MIX_TARGET=rpi3 mix deps.get
MIX_TARGET=rpi3 mix firmware
```

The firmware is generated at:

```text
_build/rpi3_dev/nerves/images/panelmeter.fw
```

List its available installation and upgrade tasks with:

```sh
fwup -l -i _build/rpi3_dev/nerves/images/panelmeter.fw
```

## Verify the generated boot partition

`fwup -l` only lists tasks; it does not prove that resources were written to
the boot filesystem. Apply the `complete` task to a temporary image and read
BOOT-A directly:

```sh
verify_image="$(mktemp /tmp/panelmeter-verify.XXXXXX.img)"

fwup -a \
  -i _build/rpi3_dev/nerves/images/panelmeter.fw \
  -d "$verify_image" \
  -t complete \
  --no-eject

mtype -i "$verify_image"@@32256 ::cmdline.txt
mtype -i "$verify_image"@@32256 ::config.txt
mdir  -i "$verify_image"@@32256 ::overlays/pwm.dtbo
```

`32256` is the BOOT-A sector offset, `63`, multiplied by 512 bytes.

Confirm that:

- `cmdline.txt` does not contain `console=serial0`;
- `config.txt` contains `dtparam=audio=off`;
- `config.txt` contains `dtoverlay=pwm,pin=18,func=2`; and
- `overlays/pwm.dtbo` exists.

Remove the temporary image after inspection:

```sh
rm -- "$verify_image"
```

On the physical device, perform the final checks:

```sh
cat /proc/cmdline
ls /sys/class/pwm/pwmchip0
```

The kernel command line must not contain `serial0`, and `pwmchip0` must
exist.

## Maintenance

`config/fwup.conf` is a copy and will not track changes to the upstream Nerves
system. After changing the `nerves_system_rpi3` version:

```sh
MIX_TARGET=rpi3 mix deps.get
MIX_TARGET=rpi3 mix nerves.artifact.details nerves_system_rpi3 \
  --copy-fwup-conf /tmp/new-fwup.conf
diff -u /tmp/new-fwup.conf config/fwup.conf

diff -u deps/nerves_system_rpi3/cmdline-a.txt config/boot/cmdline-a.txt
diff -u deps/nerves_system_rpi3/cmdline-b.txt config/boot/cmdline-b.txt
diff -u deps/nerves_system_rpi3/config.txt config/boot/config.txt
```

Regenerate the custom fwup configuration from the new artifact, reapply the
panelmeter resource changes, and repeat the build and image verification.
