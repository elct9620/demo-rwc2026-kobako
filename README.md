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
                 search_entries, upcoming_events ──▶ entries
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

## What it answers from

A bot with nothing held answers from whatever the model remembers, which for a
local community is nothing. So three feeds fill one table, once a day, and the
writer reaches it through two tools rather than being handed the table:
`search_entries` for a keyword, narrowed by source or by date, and
`upcoming_events` for what has not happened yet — which is a comparison against
now that no keyword could ask for.

A card names an event but does not link to it. The Flex DSL lends two actions,
`message` and `postback`, and neither opens a URL — so a link on a card would
be a string nobody can tap, and the tools do not return one.

| Source | What it carries |
| --- | --- |
| KKTIX | Events, with the time and venue as free text |
| YouTube | Talk recordings, and the one thumbnail worth keeping |
| Facebook | What an event was actually like, which neither of the others has |

One table rather than three, because reading them is a single query across the
lot — what separates a source from the others is a column value. Only what all
three carry is required of a row: a Facebook post has no title, and one that is
only a photo has no text either, so a column a source cannot fill stays empty
rather than being handed something invented.

Nothing revisits a row. Each run reads its source in full and hands it to a
unique index, which drops everything already seen — what a feed says about an
event does not change once published, and what does change, how many seats are
left, is not kept here. That is also why only YouTube's thumbnail is stored:
Facebook answers a signed URL that expires about four days out, and there is no
second visit to refresh it.

Each source is a task of its own in `config/recurring.yml`. Nothing is retried
and a failure only reaches the log, so a source having a bad day costs its own
rows and leaves the other two alone.

## Where to look

| Path | What it holds |
| --- | --- |
| `app/sandbox/line_flex.rb` | The boundary. `VERBS` is the whole vocabulary a script may speak |
| `app/jobs/fetch_*_entries_job.rb` | The three sources, one job each |
| `app/models/entry.rb` | What a fetched row is, how it is searched, and what the writer is told about it |
| `config/recurring.yml` | When each source is read, in the zone it says |
| `app/controllers/webhooks_controller.rb` | Where a delivery arrives and is verified |
| `app/jobs/answer_message_job.rb` | Where the card is built and the reply leaves |
| `app/tools/` | The three things the writer may ask for: two into the table, one into the sandbox |
| `app/agents/flex_message_agent.rb` | Who writes the script, and what it is allowed to answer with |
| `app/prompts/flex_message_agent/` | The brief: what it answers, how it behaves, what it has, what to do when it fails |
| `charts/demo-rwc2026-kobako/` | What k3s is asked for, with the reason beside each value |

Nothing in the brief is restated from the code. The vocabulary is one contract
in two directions — the ceiling the sandbox enforces and the list the writer
aims at — and the same holds for the tools' names, the carousel's ceiling and
today's date. A test fails if any of them reaches one side and not the other,
and another runs every card the brief shows through the sandbox, because an
example the sandbox would stop is a lesson in how to fail.

Twelve is where several of those meet: a carousel holds twelve bubbles, so it
is also every entry one answer could show, and therefore every entry a tool is
worth returning.

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
| `nokogiri` | Reads the Atom and RSS the event and video feeds answer with |

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

The feeds have the same untested half — a stub cannot tell you a source moved
or stopped answering. Running a job and counting what is in the table is what
does:

```bash
set -a && source .env.production && set +a
bin/rails runner 'FetchKktixEntriesJob.perform_now; puts Entry.group(:source).count'
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

Replacing a value later is a different command — `create` refuses a Secret that
exists, so the edited file is applied over it and the Pod restarted to read it:

```bash
kubectl -n rwc2026-demo create secret generic demo-line \
  --from-env-file=.env.production --dry-run=client -o yaml | kubectl apply -f -

kubectl -n rwc2026-demo rollout restart deployment/demo
```

`FB_PAGE_TOKEN` is the one that has to be replaced on a clock. Meta expires
*data access* ninety days from the authorisation, separately from the token,
which stays `is_valid` throughout — so nothing about the credential looks wrong
when the fetch starts failing. `debug_token` reports the date under
`data_access_expires_at`, and the new one is ninety days from whenever the page
is authorised again, not from the old expiry.

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
