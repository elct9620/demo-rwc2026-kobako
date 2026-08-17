# Dynamic Flex Message

A talk demo. The layout of a LINE Flex Message is *code* a sandbox evaluates,
not a template baked into the app.

```
LINE ──▶ POST /webhook ──▶ signature ──▶ enqueue ──▶ 200 OK
                                            │
                                     AnswerMessageJob
                                            │
                     loading animation, then FlexMessageAgent
                                            │
                                  Kobako (wasm sandbox)  ◀── layout_check
                                            │
                        line-message-builder, held on the host
                                            │
                              Flex Message ──▶ reply to LINE
```

The webhook is answered before the card exists. An LLM writes the layout, which
takes as long as it takes, and none of that is time LINE waits on — so the
sender is shown a loading animation instead. A reply token is spent once and
expires about a minute after the webhook, which is why a job that fails is not
retried and why every clock on this path is set well inside that minute.

The script is untrusted, and being written by an LLM changes nothing about
that: it never reaches the host's memory, files, network or credentials — the
only vocabulary it gets is `LineFlex::VERBS`, the Flex DSL the host lends it.
Its failures come back as values: a script that loops forever is answered with
a message saying so, not a 500. The same boundary is lent to the writer as a
tool, so it can run a script before answering with it.

The two boundaries in that path behave differently on purpose. The signature
check *rejects* — a delivery it cannot verify never gets parsed. The sandbox
*contains* — it runs code it does not trust and hands back whatever happened.

## Where to look

| Path | What it holds |
| --- | --- |
| `app/sandbox/line_flex.rb` | The boundary. `VERBS` is the whole vocabulary a script may speak |
| `app/controllers/webhooks_controller.rb` | Where a delivery arrives and is verified |
| `app/jobs/answer_message_job.rb` | Where the card is built and the reply leaves |
| `app/agents/flex_message_agent.rb` | Who writes the script, and what it is allowed to answer with |
| `app/prompts/flex_message_agent/` | The brief, which interpolates `VERBS` rather than restating it |
| `charts/demo-rwc2026-kobako/` | What k3s is asked for, with the reason beside each value |

The vocabulary is one contract in two directions: the ceiling the sandbox
enforces, and the list the writer is given to aim at. The brief interpolates it
so the two cannot drift, and a test fails if a verb reaches one and not the
other. What each verb takes is not written down yet — the brief carries one
worked example instead.

Each message opens its own chat, and the chat is kept: what was asked and what
was answered land in the SQLite database beside everything else, which is one
more place the sender's words live and is deleted with the namespace.

## The parts

| Gem | Role |
| --- | --- |
| `kobako` | Runs the layout script inside a Wasm-isolated mruby interpreter |
| `line-message-builder` | The Flex DSL the script speaks; the builder stays host-side |
| `line-bot-api` | Verifies each delivery and carries the reply |
| `ruby_llm` | Writes the layout script, and keeps the chat it was written in |

Kobako ships precompiled gems for macOS and 64-bit Linux, so installing it there
needs no Rust toolchain.

## Running it

```bash
bin/setup                  # gems and the four SQLite databases
bin/rails test
bin/ci                     # style, security and test gate
```

The half a test cannot reach — the gateway answering, the key being accepted,
the model still writing something the sandbox will run — is one real request
away:

```bash
set -a && source .env.production && set +a
bin/rails runner script/answer_once.rb
```

Answering a real message needs a channel, a key to write with, and a public
URL:

```bash
LINE_CHANNEL_SECRET=...        # verifies a delivery really came from LINE
LINE_CHANNEL_ACCESS_TOKEN=...  # authorises the reply
OPENAI_API_KEY=...             # writes the layout
bin/dev                        # then point a tunnel at :3000 and set the
                               # channel's webhook URL to <tunnel>/webhook
```

A Cloudflare AI Gateway speaks OpenAI's own API, so it is the address that
changes and nothing else — `OPENAI_API_BASE` is where it goes, and unset means
OpenAI directly. `OPENAI_MODEL` overrides the model the demo is written
against, which is `gpt-5-mini` — a generation back, because the writer needs
tools and reasoning at once and newer models only carry that pair on OpenAI's
Responses API, which `ruby_llm` does not speak yet.

```bash
OPENAI_API_BASE=https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/openai
```

`bin/dev` needs no second process: development runs jobs in-process. On the
cluster the chart asks Puma to supervise Solid Queue, which is what one replica
needs and all it needs.

## Deploying it

On stage it runs on k3s. The chart creates one Pod, one SQLite volume and one
internal address; a Cloudflare Tunnel is what puts that address on the public
HTTPS URL LINE delivers to.

Everything goes in a namespace of its own, so the whole demo is one thing to
put up and one thing to take down. The namespace and the Secret come first:
the chart names no default for the Secret, and a Pod cannot start without it.

The values go through a file rather than the command line, so they stay out of
the shell's history. `.env*` is ignored by git and by Docker, so this
one is safe where it sits:

```bash
cat > .env.production <<EOF
SECRET_KEY_BASE=$(bin/rails secret)
LINE_CHANNEL_SECRET=...
LINE_CHANNEL_ACCESS_TOKEN=...
OPENAI_API_KEY=...
OPENAI_API_BASE=https://gateway.ai.cloudflare.com/v1/<account>/<gateway>/openai
FB_PAGE_ID=...
FB_PAGE_TOKEN=...
EOF
chmod 600 .env.production
```

```bash
kubectl create namespace rwc2026-demo

kubectl -n rwc2026-demo create secret generic demo-line \
  --from-env-file=.env.production

helm upgrade -i demo oci://ghcr.io/elct9620/demo-rwc2026-kobako \
  --version 0.3.0 -n rwc2026-demo --set secretName=demo-line
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
