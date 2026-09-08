#!/usr/bin/env zsh

main() {
  emulate -LR zsh

  local id unwritable_job
  local -i popped_missing

  REPLY=
  job-queue push $test_scope
  id=$REPLY
  job-queue pop $test_scope $id
  ztr test '[[ ! -f $test_tmpdir/$test_scope/$id ]]' \
    "Removes the job from the scope's queue" \
    "Dependencies: push"

  job-queue pop $test_scope $id
  popped_missing=$?
  ztr test '(( ! popped_missing ))' \
    "Popping an already popped job is not an error"

  # zf_rm, unlike rm, prompts whenever a file is unwritable rather than only on a
  # tty, and the call site discards output -- so without -f the prompt is invisible
  # and the job is left in the queue for every other shell to wait out.
  'command' 'mkdir' -p $test_tmpdir/$test_scope
  unwritable_job=$test_tmpdir/$test_scope/$EPOCHREALTIME--unwritable
  'builtin' 'print' -r -- unwritable > $unwritable_job
  'command' 'chmod' 0444 $unwritable_job
  job-queue pop $test_scope ${unwritable_job:t} < /dev/null
  ztr test '[[ ! -f $unwritable_job ]]' \
    "Removes an unwritable job without prompting"

  'command' 'chmod' 0644 $unwritable_job 2>/dev/null
  job-queue clear $test_scope
}

main
