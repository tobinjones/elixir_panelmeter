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
