# Goal

Build an Elixir driver for the ADMX3652 and Nerves firmware for the target hardware.

# Projects

* `admx3652` — pure Elixir driver
* `panelmeter` — Nerves firmware
* `docs` — whole-project ExDoc documentation; `docs/pages/admx3652/` contains the module reference manual

# Philosophy

* Think in OTP: Processes, supervision structure, message graph
* A process is for runtime responsibility, not code organisation.
* Keep the core pure.
* Expose the hardware; hide incidental awkwardness.
* Prefer strong simple invariants.
* Start boring.
* Build incrementally.
* It takes more than a little bit of duplication to earn an abstraction.

# Driver invariants

* `ADMX3652` owns orchestration and the transport. Keep `Protocol`, `Command`, `Exchange`, and `Shadow` pure.
* `Command` describes one SCPI operation; `Exchange` tracks one verified wire conversation. Only one exchange may be active.
* Update shadow state only after verified success. Raw writes or protocol ambiguity enter `:desynchronised`.
* Publish every sent and received `%ADMX3652.Line{}` in order; only sent or successfully claimed lines receive an exchange ID.

# Talking to the board

The RPi3 runs this firmware and names itself `panelmeter@<eth0 ip>` once eth0
has a DHCP lease (`Panelmeter.Distribution`). Drive it from the `elixir-session`
skill; the board's address and the cluster cookie come from `.session.env`
(git-ignored, copy `.session.env.example`), so run from the repo root. Below,
`$BOARD` is that address.

The bridge needs Elixir on `PATH`, which only the flake provides:

```sh
nix develop --command bash -c '~/.claude/skills/elixir-session/session.sh up'
session.sh status                       # peers should list panelmeter@$BOARD
session.sh eval ':erpc.call(:"panelmeter@'$BOARD'", ADMX3652, :disable, [Panelmeter.Meter])'
```

Build and flash with `nix develop`, `MIX_TARGET=rpi3`: `mix firmware` then
`mix upload $BOARD` — no SD card swap, the board reboots itself. A target build
needs the cluster cookie and gossip secret from `config/site.exs`, or it stops
with an error saying so.

## Watching the line stream

`Phoenix.PubSub.subscribe/2` subscribes `self()`, and both the evaluator and an
`:erpc` worker are throwaway processes, so subscribing directly sees nothing.
Spawn a forwarder *on the board* that subscribes itself and relays to `inbox()`.
An interpreted closure ships across; a fun from a compiled module would not.

```sh
session.sh eval <<'ELIXIR'
me = inbox()
:erpc.call(:"panelmeter@BOARD_IP", :erlang, :spawn, [fn ->
  Phoenix.PubSub.subscribe(Panelmeter.PubSub, "admx3652:lines")
  loop = fn f -> receive do msg -> send(me, {:line, msg}); f.(f) end end
  loop.(loop)
end])
ELIXIR
session.sh flush                        # timestamped %ADMX3652.Line{} structs
```

It is temporary by design: it dies with the node connection and does not
survive a board reboot. Re-spawn it after a `:nodeup`.
