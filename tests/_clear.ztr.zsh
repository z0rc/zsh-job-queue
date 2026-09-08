#!/usr/bin/env zsh

main() {
  emulate -LR zsh

  local id

  REPLY=
  job-queue push $test_scope
  id=$REPLY
  job-queue clear $test_scope
  ztr test '[[ ! -d $test_tmpdir/$test_scope ]]' \
    "Removes the scope's queue" \
    "Dependencies: push"

  REPLY=
  job-queue push $test_scope
  id=$REPLY
  REPLY=
  job-queue push $test_scope_2
  job-queue clear $test_scope_2
  ztr test '[[ -f $test_tmpdir/$test_scope/$id ]] \
      && [[ ! -d $test_tmpdir/$test_scope_2 ]]' \
    "Leaves other scopes' queues alone" \
    "Dependencies: push"

  job-queue clear $test_scope

  # An unwritable job file must not leave zf_rm waiting on a discarded prompt
  'command' 'mkdir' -p $test_tmpdir/$test_scope
  'builtin' 'print' -r -- unwritable > $test_tmpdir/$test_scope/$EPOCHREALTIME--unwritable
  'command' 'chmod' 0444 $test_tmpdir/$test_scope/*(N)
  job-queue clear $test_scope < /dev/null
  ztr test '[[ ! -d $test_tmpdir/$test_scope ]]' \
    "Removes an unwritable job without prompting"

  'command' 'chmod' -R 0755 $test_tmpdir/$test_scope 2>/dev/null
  'command' 'rm' -rf $test_tmpdir/$test_scope
}

main
