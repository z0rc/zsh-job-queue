#!/usr/bin/env zsh

main() {
  emulate -LR zsh

  local id job_file timeout_output timeout_output_file unwritable_abandoned \
    waiter_output waiter_reply_file
  local -a remaining
  local -i entered overlaps stuck_waiter_pid stuck_waiter_running waiter_pid \
    waiter_running

  # Runs $1 concurrent shells which each take a turn in the queue, log entering
  # and leaving it, and hold it briefly. Pass 0 as $2 to skip the queue entirely.
  # Sets entered and overlaps.
  function _job_queue_test:contend() {
    local holder kind log prev
    local -i i lock n

    n=$1
    lock=$2
    log=$test_tmpdir/contended.$RANDOM

    'command' 'mkdir' -p $test_tmpdir
    'command' 'rm' -f $log
    'command' 'touch' $log

    for i in {1..$n}; do
      (
        local worker_id
        . $job_queue_dir/zsh-job-queue.zsh ''
        if (( lock )); then
          REPLY=
          job-queue push $test_scope_2
          worker_id=$REPLY
        fi
        'builtin' 'print' -r -- "enter $i" >> $log
        'command' 'sleep' 0.05
        'builtin' 'print' -r -- "exit $i" >> $log
        (( lock )) && job-queue pop $test_scope_2 $worker_id
      ) &
    done
    wait

    entered=0
    overlaps=0
    prev=

    while read -r kind holder; do
      if [[ $kind == enter ]]; then
        (( entered++ ))
        [[ -n $prev ]] && (( overlaps++ ))
        prev=$holder
      else
        prev=
      fi
    done < $log

    'command' 'rm' -f $log
  }

  REPLY=
  job-queue push $test_scope
  ztr test '(( ! $? ))' \
    "Exits without error"
  id=$REPLY

  ztr test '[[ -n $id ]]' \
    "Sets the job id in REPLY"

  ztr test '[[ -f $test_tmpdir/$test_scope/$id ]]' \
    "Adds the job to the scope's queue"

  # handle_timeout parses the timestamp back off the front of the id with %%-*
  ztr test '[[ ${id%%-*} == <->.<-> ]]' \
    "Prefixes the job id with a fractional epoch timestamp"

  job-queue pop $test_scope $id

  REPLY=
  job-queue push $test_scope $test_description $test_url
  id=$REPLY
  job_file=$test_tmpdir/$test_scope/$id
  ztr test '[[ ${${(f)"$(< $job_file)"}[1]} == $test_description ]] \
      && [[ ${${(f)"$(< $job_file)"}[2]} == $test_url ]]' \
    "Records the job description and support ticket url"
  job-queue pop $test_scope $id

  _job_queue_test:contend 8 1
  ztr test '(( entered == 8 )) && (( overlaps == 0 ))' \
    "Holds the queue for one job at a time" \
    "Dependencies: pop"

  _job_queue_test:contend 8 0
  ztr test '(( entered == 8 )) && (( overlaps > 0 ))' \
    "Negative control: the same check reports overlap when the queue is not used"

  # A job stamped in the past, as if its shell was killed without popping
  'command' 'mkdir' -p $test_tmpdir/$test_scope
  'builtin' 'print' -r -- "$test_description\n$test_url" \
    > $test_tmpdir/$test_scope/$(( EPOCHREALTIME - 600 ))--abandoned
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=$test_timeout
  timeout_output_file=$test_tmpdir/timeout.out
  REPLY=
  job-queue push $test_scope > $timeout_output_file 2>&1
  id=$REPLY
  timeout_output=$(< $timeout_output_file)
  'command' 'rm' -f $timeout_output_file
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=30

  ztr test '[[ $timeout_output == *"has timed out"* ]] \
      && [[ $timeout_output == *$test_url* ]]' \
    "Reports a timed out job ahead of it in the queue"

  remaining=( $test_tmpdir/$test_scope/*(N) )
  ztr test '(( ${#remaining} == 1 )) && [[ -f $test_tmpdir/$test_scope/$id ]]' \
    "Drops the timed out job and takes its turn"

  job-queue pop $test_scope $id
  job-queue clear $test_scope

  # Same, but the abandoned job is unwritable. Without -f, zf_rm cannot remove it
  # and the notice is reprinted forever instead of the queue draining, so give the
  # waiter a deadline rather than letting a regression hang the suite.
  'command' 'mkdir' -p $test_tmpdir/$test_scope
  unwritable_abandoned=$test_tmpdir/$test_scope/$(( EPOCHREALTIME - 600 ))--abandoned
  'builtin' 'print' -r -- $test_description > $unwritable_abandoned
  'command' 'chmod' 0444 $unwritable_abandoned
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=$test_timeout
  (
    . $job_queue_dir/zsh-job-queue.zsh ''
    REPLY=
    job-queue push $test_scope
  ) > /dev/null 2>&1 < /dev/null &
  stuck_waiter_pid=$!
  for i in {1..100}; do
    'command' 'kill' -0 $stuck_waiter_pid 2>/dev/null || break
    'command' 'sleep' 0.1
  done
  stuck_waiter_running=0
  'command' 'kill' -0 $stuck_waiter_pid 2>/dev/null && stuck_waiter_running=1
  (( stuck_waiter_running )) && 'command' 'kill' -9 $stuck_waiter_pid 2>/dev/null
  wait $stuck_waiter_pid 2>/dev/null
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=30

  ztr test '(( ! stuck_waiter_running )) && [[ ! -f $unwritable_abandoned ]]' \
    "Removes an unwritable timed out job rather than waiting on a hidden prompt"

  'command' 'chmod' -R 0755 $test_tmpdir/$test_scope 2>/dev/null
  job-queue clear $test_scope

  # Wait for a turn behind a job which is then cleared out from under us. The
  # timeout is long, so only the clear can release the waiter.
  'command' 'mkdir' -p $test_tmpdir/$test_scope
  'builtin' 'print' -r -- holder > $test_tmpdir/$test_scope/$EPOCHREALTIME--holder
  waiter_output=$test_tmpdir/waiter.out
  waiter_reply_file=$test_tmpdir/waiter.reply
  'command' 'rm' -f $waiter_reply_file
  (
    . $job_queue_dir/zsh-job-queue.zsh ''
    REPLY=
    job-queue push $test_scope
    'builtin' 'print' -r -- $REPLY > $waiter_reply_file
  ) > $waiter_output 2>&1 &
  waiter_pid=$!
  'command' 'sleep' 0.3
  job-queue clear $test_scope
  for i in {1..50}; do
    'command' 'kill' -0 $waiter_pid 2>/dev/null || break
    'command' 'sleep' 0.1
  done
  waiter_running=0
  'command' 'kill' -0 $waiter_pid 2>/dev/null && waiter_running=1
  (( waiter_running )) && 'command' 'kill' -9 $waiter_pid 2>/dev/null
  wait $waiter_pid 2>/dev/null

  ztr test '(( ! waiter_running ))' \
    "Stops waiting when its own job is cleared away" \
    "Dependencies: clear"

  ztr test '[[ -z $(< $waiter_output) ]]' \
    "Unwinds quietly when its own job is cleared away" \
    "An empty front of queue must not reach the timestamp arithmetic"

  # wait_turn reads the front of the queue into REPLY, so it needs its own copy
  ztr test '[[ $(< $waiter_reply_file) == <->.<->--* ]]' \
    "Still reports its own job id in REPLY when its job is cleared away"

  'command' 'rm' -f $waiter_output $waiter_reply_file
  job-queue clear $test_scope

  unfunction -m _job_queue_test:contend
}

main
