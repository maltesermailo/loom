# loom-meta

The umbrella (superproject) for Loom. It tracks **nothing of its own** except
three submodules and a couple of helper files:

- `spec/` — the normative protocol spec + conformance vectors (`loom-spec`).
- `host/` — the Rust host workspace (`loom-host`).
- `client/` — the C++ client (`loom-client`).

Each is a fully independent git repo; this superproject only *pins* which commit
of each belongs together.

## Clone

```sh
git clone --recurse-submodules https://github.com/maltesermailo/loom-meta.git
# already cloned without --recurse-submodules?
git submodule update --init --recursive
```

Submodule URLs in `.gitmodules` are the absolute GitHub forge URLs, so a fresh
recursive clone resolves them correctly.

## Day-to-day workflow

Work inside a subrepo exactly as you normally would — `cd host`, branch, commit,
push. Nothing about the subrepos changes because they live under this umbrella.

When you want the superproject to pin the new state of one or more subrepos:

```sh
./sync.sh status   # branch / dirty / ahead-behind / whether gitlinks are stale
./sync.sh pull     # fetch + fast-forward each subrepo on its branch
./sync.sh record   # commit the moved gitlinks here (message lists old..new hashes)
./sync.sh push     # push each subrepo, then this superrepo (skips where no remote)
```

`record` is the important one: the superrepo only advances its pin of a subrepo
when you explicitly run it. A `STALE` gitlink in `status` just means a subrepo has
moved ahead of what the superrepo currently pins — run `record` to catch up.

## Nested-submodule note (not a bug)

`host/` and `client/` **each carry their own `spec/` submodule**, pinned at
whatever spec commit that repo was built against. That pin can lag this
superproject's top-level `spec/` — that is intended. The top-level `spec/` is the
"current" spec; a subrepo's nested `spec/` is the exact spec it was last validated
against. They converge when you bump a subrepo's nested spec and `record` it here.
