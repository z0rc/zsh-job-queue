#!/usr/bin/env zsh

main() {
  emulate -LR zsh

  local id
  local -a forked_uuids ids
  local -i i

  # generate-id is unfunction'd after each call, so exercise it through push
  for i in {1..200}; do
    REPLY=
    job-queue push $test_scope
    ids+=$REPLY
    job-queue pop $test_scope $REPLY
  done
  ztr test '(( ${#${(u)ids[@]}} == ${#ids} ))' \
    "Generates a distinct id for every job" \
    "Dependencies: push, pop"

  # $RANDOM is seeded from the pid, which zsh does not change for a subshell, so
  # without the reseed every fork of one parent generates the same uuid
  for i in {1..20}; do
    forked_uuids+=$(
      REPLY=
      job-queue push $test_scope
      'builtin' 'print' -r -- ${REPLY#*--}
      job-queue pop $test_scope $REPLY
    )
  done
  ztr test '(( ${#${(u)forked_uuids[@]}} > 1 ))' \
    "Generates distinct ids in subshells of one parent" \
    "Dependencies: push, pop"

  REPLY=
  job-queue push $test_scope
  id=$REPLY
  job-queue pop $test_scope $id
  # 8-4-4-4-12, version nibble 4, variant nibble 8-b. (#cN) would need extended_glob
  ztr test '[[ ${id#*--} == ????????-????-4???-[89ab]???-???????????? ]]' \
    "Shapes the id like a v4 uuid" \
    "Dependencies: push, pop"

  job-queue clear $test_scope
}

main
