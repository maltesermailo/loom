#!/bin/sh
# loom-meta submodule helper. Plain POSIX sh; no set -e so pull/push report
# per-repo failures instead of aborting the whole run.
set -u
cd "$(dirname "$0")" || exit 1
SUBS="spec host client"

cmd_status() {
  for s in $SUBS; do
    br=$(git -C "$s" rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -n "$(git -C "$s" status --porcelain)" ]; then dirty=dirty; else dirty=clean; fi
    ab=$(git -C "$s" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null |
         awk '{printf "behind:%s ahead:%s",$1,$2}')
    [ -n "$ab" ] || ab="no-upstream"
    case "$(git submodule status -- "$s" 2>/dev/null | cut -c1)" in
      +) link=STALE ;; -) link=uninit ;; *) link=pinned ;;
    esac
    printf '%-7s %-6s %-6s %-22s gitlink:%s\n' "$s" "$br" "$dirty" "$ab" "$link"
  done
}

cmd_pull() {
  for s in $SUBS; do
    old=$(git -C "$s" rev-parse --short HEAD)
    if git -C "$s" rev-parse '@{u}' >/dev/null 2>&1; then
      git -C "$s" fetch --quiet
      git -C "$s" merge --ff-only '@{u}' >/dev/null 2>&1 || echo "$s: not fast-forward, skipped"
    else
      echo "$s: no upstream, skipped"
    fi
    new=$(git -C "$s" rev-parse --short HEAD)
    if [ "$old" != "$new" ]; then echo "$s: $old -> $new"; else echo "$s: unchanged ($new)"; fi
  done
}

cmd_record() {
  msg="meta: update submodule gitlinks"
  changed=0
  for s in $SUBS; do
    old=$(git rev-parse --short "HEAD:$s" 2>/dev/null || echo 0000000)
    new=$(git -C "$s" rev-parse --short HEAD)
    if [ "$old" != "$new" ]; then
      git add "$s"
      msg=$(printf '%s\n  %s: %s..%s' "$msg" "$s" "$old" "$new")
      changed=1
    fi
  done
  if [ "$changed" = 0 ]; then echo "no gitlink changes to record"; return 0; fi
  git commit -m "$msg"
}

cmd_push() {
  for s in $SUBS; do
    if [ -n "$(git -C "$s" remote)" ]; then
      git -C "$s" push || echo "$s: push failed"
    else
      echo "$s: no remote, skipped"
    fi
  done
  if [ -n "$(git remote)" ]; then git push || echo "super: push failed"; else
    echo "super: no remote, skipped"; fi
}

case "${1:-}" in
  status) cmd_status ;;
  pull)   cmd_pull ;;
  record) cmd_record ;;
  push)   cmd_push ;;
  *) echo "usage: $0 {status|pull|record|push}" >&2; exit 2 ;;
esac
