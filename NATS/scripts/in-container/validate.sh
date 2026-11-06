#!/bin/sh
# Runs inside nats-box as app-admin for scripts/validate.sh. Works only on the
# temporary stream VALIDATE_<run id>; never touches application streams.
#   validate.sh <phase> <run id> [count]
# phases: setup | publish | consume | expect <messages> <ack floor> | leader | cleanup
set -eu
phase="${1:?phase}"
run="${2:?run id}"
stream="VALIDATE_$run"
subject="validate.$run"
say() { printf '[validate] %s\n' "$*"; }

case "$phase" in
  setup)
    nats stream add "$stream" --subjects "$subject.>" --storage file --replicas 3 \
      --retention limits --discard old --max-bytes 64MiB --max-age 1h --dupe-window 2m \
      --description "temporary stream for scripts/validate.sh" --defaults >/dev/null
    nats consumer add "$stream" validator --pull --ack explicit --deliver all \
      --replay instant --max-deliver 5 --wait 30s --defaults >/dev/null
    i=0
    until nats stream info "$stream" --json | jq -e '
        .cluster.leader != null and .cluster.leader != ""
        and ([.cluster.leader] + [.cluster.replicas[].name] | unique | length) == 3
        and ([.cluster.replicas[] | select(.current != true)] | length) == 0' >/dev/null; do
      i=$((i + 1))
      [ "$i" -lt 30 ] || { say "FAIL R3 placement"; nats stream info "$stream" --json | jq -c .cluster; exit 1; }
      sleep 1
    done
    say "OK   $stream placed on 3 distinct servers, all current: $(nats stream info "$stream" --json | jq -c '[.cluster.leader] + [.cluster.replicas[].name]')"
    ;;
  publish)
    n="${3:-100}"
    # --jetstream waits for a PubAck per message: the stream leader only acks
    # after a quorum (2 of 3) stored it.
    nats publish "$subject.msg" "validation message {{Count}}" --count "$n" --jetstream -q >/dev/null
    say "OK   published $n messages, every one acknowledged by JetStream"
    ;;
  consume)
    n="${3:-100}"
    got="$(nats consumer next "$stream" validator --count "$n" --ack --timeout 10s 2>&1 | grep -c 'Acknowledged message' || true)"
    [ "$got" = "$n" ] || { say "FAIL consumed and acked $got of $n"; exit 1; }
    say "OK   durable consumer delivered and acked $n messages"
    ;;
  expect)
    msgs="${3:?messages}"
    floor="${4:?ack floor}"
    s="$(nats stream info "$stream" --json)"
    c="$(nats consumer info "$stream" validator --json)"
    gm="$(printf '%s' "$s" | jq -r .state.messages)"
    gl="$(printf '%s' "$s" | jq -r .state.last_seq)"
    gf="$(printf '%s' "$c" | jq -r .ack_floor.stream_seq)"
    if [ "$gm" = "$msgs" ] && [ "$gl" = "$msgs" ] && [ "$gf" = "$floor" ]; then
      say "OK   stream holds $gm messages (last seq $gl), consumer ack floor $gf"
    else
      say "FAIL expected messages=$msgs ack_floor=$floor, got messages=$gm last_seq=$gl ack_floor=$gf"
      exit 1
    fi
    ;;
  leader)
    nats stream info "$stream" --json | jq -r .cluster.leader
    ;;
  cleanup)
    nats stream rm "$stream" -f >/dev/null 2>&1 || true
    say "removed $stream"
    ;;
  *)
    echo "unknown phase $phase" >&2
    exit 64
    ;;
esac
