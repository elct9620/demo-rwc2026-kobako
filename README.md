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
| `charts/demo-rwc2026-kobako/` | What k3s is asked for, with the reason beside each value |

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

## Deploying it

On stage it runs on k3s. The chart creates one Pod, one SQLite volume and one
internal address; a Cloudflare Tunnel is what puts that address on the public
HTTPS URL LINE delivers to.

Everything goes in a namespace of its own, so the whole demo is one thing to
put up and one thing to take down. The namespace and the Secret come first:
the chart names no default for the Secret, and a Pod cannot start without it.

The three values go through a file rather than the command line, so they stay
out of the shell's history. `.env*` is ignored by git and by Docker, so this
one is safe where it sits:

```bash
cat > .env.production <<EOF
SECRET_KEY_BASE=$(bin/rails secret)
LINE_CHANNEL_SECRET=...
LINE_CHANNEL_ACCESS_TOKEN=...
EOF
chmod 600 .env.production
```

```bash
kubectl create namespace rwc2026-demo

kubectl -n rwc2026-demo create secret generic demo-line \
  --from-env-file=.env.production

helm upgrade -i demo oci://ghcr.io/elct9620/demo-rwc2026-kobako \
  --version 0.1.0 -n rwc2026-demo --set secretName=demo-line
```

`SECRET_KEY_BASE` has to stay put: changing it invalidates everything already
signed with it.

Then point the tunnel at the address the chart prints, and set the channel's
webhook URL to that tunnel's `/webhook`:

```
http://demo.rwc2026-demo.svc.cluster.local   →   https://rwc2026-demo.aotoki.dev
```

The two layers move separately, and each has its own way of moving:

| Changed | Published as | Picked up by |
| --- | --- | --- |
| The app | `ghcr.io/elct9620/demo-rwc2026-kobako/app:latest` | `kubectl -n rwc2026-demo rollout restart deployment/demo` |
| The chart | `oci://ghcr.io/elct9620/demo-rwc2026-kobako` | Bump `version` in `Chart.yaml`, then `helm upgrade -n rwc2026-demo --version` |

The claim stays `Pending` until the Pod is scheduled — that is `local-path`
binding the volume to a node, not a failure.

## Taking it down

```bash
kubectl delete namespace rwc2026-demo
```

That is the whole of it: the Pod, the Secret, and the claim. The claim going
is what takes the SQLite files with it, because `local-path` reclaims the
directory it made on the node rather than keeping it.
