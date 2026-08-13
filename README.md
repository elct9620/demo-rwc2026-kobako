# Dynamic Flex Message

A talk demo. The layout of a LINE Flex Message is *code* an LLM writes and a
sandbox evaluates, not a template baked into the app.

```
ruby_llm ──▶ mruby layout script ──▶ Kobako (wasm sandbox) ──▶ Flex Message
                                            │
                          line-message-builder, held on the host
```

The script is untrusted. It never reaches the host's memory, files, network or
credentials — the only vocabulary it gets is the Flex DSL the host lends it, and
its failures (timeout, resource limit, exception) come back as values the app
shows rather than exceptions that leak host detail.

## The parts

| Gem | Role |
| --- | --- |
| `kobako` | Runs the layout script inside a Wasm-isolated mruby interpreter |
| `line-message-builder` | The Flex DSL the script speaks; the builder stays host-side |
| `ruby_llm` | Writes the layout script |
| `line-bot-api` | LINE Messaging API client and message types |

Kobako ships precompiled platform gems, so installing it needs no Rust toolchain.

## Running it

```bash
bin/setup                  # gems and the four SQLite databases
bin/dev                    # http://localhost:3000
bin/rails test
bin/ci                     # style, security and test gate
```

This exists to be read and shown on stage, not deployed.
