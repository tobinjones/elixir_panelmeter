# Goal

Build an Elixir driver for the ADMX3652 and Nerves firmware for the target hardware.

# Philosophy

* Think in OTP: Processes, supervision structure, message graph
* A process is for runtime responsibility, not code organisation.
* Keep the core pure.
* Expose the hardware; hide incidental awkwardness.
* Prefer strong simple invariants.
* Start boring.
* Build incrementally.
* It takes more than a little bit of duplication to earn an abstraction.
