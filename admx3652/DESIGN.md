# ADMX3652 driver architecture

Design notes for the `admx3652` driver. Written against firmware Rev. 4.9.2 as
documented in `docs/pages/admx3652/`.

## Context

Existing pieces: a pure line classifier (`ADMX3652.Protocol.decode/1`), a
`Transport` behaviour delivering `{:admx3652_transport, t, {:line, line}}`
messages, and a `gen_statem` skeleton (`ADMX3652`) with lifecycle states
`:off | :starting | :configuring | :ready | :desynchronised`.

Simplifying assumptions asserted for this design:

- exclusive use of the module (this driver is the only host talking to it);
- baud changes happen out of band (not in scope for the driver);
- silent (set) commands are verified by reading the error queue.

Design under consideration: caller → module function → gen_statem → driver
writes line(s) and registers a transaction/handler in state, which consumes
classified incoming lines until "done", then replies to the caller.

## Verdict

The architecture is sound and well matched to this device. Reasons, grounded in
the documented firmware behaviour:

- **The device has no response tagging**, so correlation is only possible by
  serialising: exactly one in-flight transaction, everything else queued.
  Exclusive use makes this a strong, simple invariant.
- **Responses are irregular** — 0 lines (silent sets), 1 line, fixed-N lines
  with no sentinel (`CONFIGURE:INF?` = 3, `SYST:CAL:DATA?` = 15), or
  free-text-then-error (`Error: Baudrate shall be...` + `**ERROR: -200,...`).
  Only the transaction knows what "done" looks like, so completion logic *must*
  live per-command, not in the reader. The proposed handler-until-done is
  exactly right.
- **Unsolicited traffic interleaves with responses** — streamed measurements at
  up to 1 kSPS, `ChannelN OVERLOAD`, async `**ERROR:` lines, startup/reset
  messages. So the transaction must be able to say "not mine, pass it on" per
  line. A consume-or-pass step function over `Protocol.decoded()` values
  handles this cleanly; e.g. a `MEAS? 1` transaction claims
  `{:measurement, 1, v}` and passes `{:measurement, 2, v}` from a streaming
  channel 2.

Alternatives considered and rejected:

- **Process-per-request** (Task/handler proc): extra concurrency buys nothing
  for a strictly serialised device and muddies transport ownership.
- **gen_statem state per command**: state explosion; per-request logic belongs
  in data, lifecycle in the state atom (the split the skeleton already has).

## Moving parts

```text
caller ──call──▶ ADMX3652 (gen_statem, owns lifecycle + one in-flight txn + FIFO queue)
                    │  ▲
             write  │  │ {:line, line} ──▶ Protocol.decode/1 (pure)
                    ▼  │
                 Transport (UART framing on CRLF; one terminated command per write)

ADMX3652.Command — pure command specs: writes + step fun + timeout   (new)
listener pid    — receives passed-through measurements/overloads     (new, minimal)
```

### 1. `ADMX3652.Command` — pure transaction spec (new module)

Make the transaction a pure data structure built by pure constructors, so the
whole command layer is unit-testable by feeding it decoded lines with no
process involved (matches "keep the core pure", "start boring"):

```elixir
defmodule ADMX3652.Command do
  alias ADMX3652.Protocol

  @enforce_keys [:writes, :step]
  defstruct [:writes, :step, acc: nil, timeout: 1_000]

  @type step_result ::
          {:cont, acc :: term()}               # consumed, still waiting
          | {:write, iodata(), acc :: term()}  # consumed, next phase: send more
          | {:done, result :: term()}          # transaction complete, reply to caller
          | :pass                              # not mine — default-route this line

  @type t :: %__MODULE__{
          writes: [iodata()],                  # initial command line(s), sans terminator
          step: (Protocol.decoded(), acc :: term() -> step_result()),
          acc: term(),
          timeout: timeout()
        }
end
```

The `{:write, ...}` result enables multi-phase transactions — needed for the
error-queue check below — while keeping the engine dumb.

Constructor examples:

```elixir
# Simple query: one classified line completes it.
def query_range(channel) do
  %Command{
    writes: ["CONFigure:VOLTage:DC? #{channel}"],
    step: fn
      {:range, ^channel, value}, _acc -> {:done, {:ok, value}}
      _other, _acc -> :pass
    end
  }
end

# Silent set, verified via the error queue:
# phase 1 sends the set + SYST:ERR:COUNt? in one transaction;
# a zero count is the ack; a nonzero count drains the queue and reports.
def set_range(channel, range) do
  %Command{
    writes: ["CONFigure:VOLTage:DC #{channel},#{range}", "SYSTem:ERRor:COUNt?"],
    acc: {:await_count, []},
    step: fn
      {:integer, 0}, {:await_count, []} -> {:done, :ok}
      {:integer, n}, {:await_count, []} -> {:write, "SYSTem:ERRor?", {:drain, n, []}}
      {:error_queue, code, msg}, {:drain, 1, errs} ->
        {:done, {:error, {:device, Enum.reverse([{code, msg} | errs])}}}
      {:error_queue, code, msg}, {:drain, n, errs} ->
        {:write, "SYSTem:ERRor?", {:drain, n - 1, [{code, msg} | errs]}}
      _other, _acc -> :pass  # async **ERROR: duplicate, interleaved measurements, etc.
    end
  }
end

# Fixed-N multi-line query: acc counts lines down; done at zero.
```

Note the async `**ERROR:` line is deliberately *not* used for correlation — it
duplicates the queued entry and its timing is loose. Draining the queue keeps
the "error queue empty between commands" invariant, which is what makes
per-command checking sound.

### 2. `Protocol` — one small addition

`SYST:ERR:COUNt?` (and `*OPC?`/`*ESR?` etc.) return a bare integer line, which
currently classifies as `:unknown`. Add a context-free `{:integer, n}` clause
for bare-integer lines; the transaction supplies the context. No other changes
needed — the existing classifier's tagged tuples are exactly what step
functions want to pattern-match on.

### 3. `ADMX3652` gen_statem — engine + lifecycle

Data grows to:

```elixir
defstruct [:transport_mod, :transport, :listener,
           current: nil,          # {%Command{}, GenServer.from()} | nil
           queue: :queue.new()]   # pending {%Command{}, from}
```

Public API stays thin: each function builds a `Command` purely, then
`:gen_statem.call(meter, {:command, cmd})`.

Event handling in `:ready`:

- `{:call, from}, {:command, cmd}` — if `current == nil`: write each of
  `cmd.writes` as its own terminated transport write (the firmware discards
  fragments and requires one full command per host write), set
  `{{:timeout, :transaction}, cmd.timeout, :expired}`, store `current`.
  Otherwise enqueue. (FIFO queue in data; boring and introspectable.
  gen_statem `postpone` would also work but hides the queue from
  `:sys.get_state`.)
- `:info, {:admx3652_transport, t, {:line, line}}` —
  `decoded = Protocol.decode(line)`; if a transaction is current, run
  `step.(decoded, acc)`:
  - `{:cont, acc}` / `{:write, iodata, acc}` → update, optionally write more
  - `{:done, result}` → reply to `from`, cancel timeout, pop queue and start next
  - `:pass` → default routing (below)

  No transaction → default routing.
- `{:timeout, :transaction}` — reply `{:error, :timeout}` to the caller, drop
  the queue with `{:error, :desynchronised}` replies (or keep and retry — start
  with drop, it's simpler), transition to `:desynchronised`.

Default routing (applies both idle and mid-transaction via `:pass`):

- `{:measurement, ch, v}` / `{:overload, ch}` → send to `listener`
  (`{:admx3652, meter_pid, decoded}`). Start with a single listener pid option
  defaulting to nothing/discard; a subscribe API can come later.
- `{:device_message, :ready}` arriving unexpectedly → the device rebooted under
  us → fail any current transaction and go to `:configuring` (settings are
  volatile; reapply everything).
- `{:async_error, ...}` with no transaction → log; with exclusive use this
  signals a hardware complaint (ADC/power lines classify as `:unknown` today —
  log those too).
- `:unknown` → log at debug. Never let it complete or abort a transaction.

Lifecycle states (already sketched in the skeleton — this fills in the intent):

- `:off` — transport disabled; commands rejected `{:error, :off}`.
- `:starting` — after power-on/`*RST`: ignore everything until
  `{:device_message, :ready}` (~4.6 s; use a generous state_timeout), then
  `:configuring`.
- `:configuring` — establish the baseline using the driver's own command engine
  internally: `CONF:CONTINUOUS:READ 1,OFF` / `2,OFF`, `*CLS`, quiet-period
  drain, then apply desired config. Then `:ready`.
- `:desynchronised` — entered from init-with-enabled-transport, transaction
  timeout, or transport error. Recovery: stop streams, `*CLS`, drain until
  quiet, probe `*IDN?`; success → `:configuring`.

### 4. Transport contract clarification

Document on the behaviour: `write/2` is one complete command per call and the
implementation must issue it as a single UART write with terminator appended
(firmware does not reassemble fragments). Incoming framing is CRLF with the
~1 ms split-line behaviour already handled by line-framing.

## Risks / accepted costs

- **Closures in gen_statem data**: step funs are anonymous functions held in
  state. Fine for this stage (no hot upgrades planned); if it ever grates, the
  same shape converts mechanically to a `{module, fun, args}` or behaviour
  form.
- **Streamed measurements during transactions** at 460800/1 kSPS mean the step
  fun runs per line; it's a single pattern match — negligible.
- **`MEAS?` on a streaming channel** silently flips it to single-read
  (documented firmware quirk). The command layer should either forbid
  `measure/2` on a channel the driver believes is streaming, or model the mode
  flip in shadow state. Defer; note it in the command doc.
- Timeout choice per command matters: `*RST` ~4.6 s to ready, NPLC=100 reads
  ~4 s. Per-command `timeout` field covers this.

## Suggested build order (incremental, each step testable)

1. `Protocol`: add `{:integer, n}` clause (+ tests).
2. `ADMX3652.Command` with 3–4 representative constructors: `identify/0`
   (1-line query), `set_range/2` (silent set + error-queue check),
   `configuration/0` (fixed-3-line), `measure/2` (claims one
   `{:measurement, ch, _}`). Pure tests: fold decoded lines through `step`,
   including interleaved stream/async-error lines.
3. gen_statem engine in `:ready` only: command call, line routing, queue,
   timeout → `:desynchronised`. Tests via existing `TestTransport` (inject
   lines, assert writes and replies).
4. Listener pass-through for measurements/overloads.
5. Lifecycle: `:starting` (wait for ready), `:configuring`, `:desynchronised`
   recovery.
