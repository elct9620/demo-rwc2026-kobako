# Dynamic Flex Message

A talk demo. The layout of a LINE Flex Message is *code* a sandbox evaluates,
not a template baked into the app.

```
LINE ──▶ POST /webhook ──▶ signature ──▶ layout script
                                              │
                                    Kobako (wasm sandbox)
                                              │
                        line-message-builder, held on the host
                                              │
                              Flex Message ──▶ reply to LINE
```

The script is untrusted. It never reaches the host's memory, files, network or
credentials — the only vocabulary it gets is `LineFlex::VERBS`, the Flex DSL the
host lends it. Its failures come back as values: a script that loops forever is
answered with a message saying so, not a 500.

The two boundaries in that path behave differently on purpose. The signature
check *rejects* — a delivery it cannot verify never gets parsed. The sandbox
*contains* — it runs code it does not trust and hands back whatever happened.

## Where to look

| Path | What it holds |
| --- | --- |
| `app/sandbox/line_flex.rb` | The boundary. `VERBS` is the whole vocabulary a script may speak |
| `app/controllers/webhooks_controller.rb` | Where a message arrives and a reply leaves |

The script the demo runs is fixed. Handing that job to `ruby_llm` comes after
the vocabulary is written down as a contract worth generating against.

## The parts

| Gem | Role |
| --- | --- |
| `kobako` | Runs the layout script inside a Wasm-isolated mruby interpreter |
| `line-message-builder` | The Flex DSL the script speaks; the builder stays host-side |
| `line-bot-api` | Verifies each delivery and carries the reply |
| `ruby_llm` | Will write the layout script |

Kobako ships precompiled gems for macOS and 64-bit Linux, so installing it there
needs no Rust toolchain.

## Running it

```bash
bin/setup                  # gems and the four SQLite databases
bin/rails test
bin/ci                     # style, security and test gate
```

Answering a real message needs a channel and a public URL:

```bash
LINE_CHANNEL_SECRET=...        # verifies a delivery really came from LINE
LINE_CHANNEL_ACCESS_TOKEN=...  # authorises the reply
bin/dev                        # then point a tunnel at :3000 and set the
                               # channel's webhook URL to <tunnel>/webhook
```

This exists to be read and shown on stage, not deployed.
