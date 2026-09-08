#!/usr/bin/env zsh

# Tests require ztr
# https://github.com/olets/zsh-test-runner

# Run the test suite by
# sourcing this file
#
# ```
# . <path to this file>
# ```
#
# or by running it in a subshell with ZTR_PATH passed in as ztr_path
#
# ```
# ztr_path=$ZTR_PATH zsh <path to this file>
# ```

main() {
  emulate -LR zsh

  local \
    cmd \
    job_queue_dir \
    job_queue_debug_saved \
    job_queue_privileged_tmpdir_saved \
    job_queue_timeout_saved \
    job_queue_tmpdir_saved \
    test_description \
    test_dir \
    test_scope \
    test_scope_2 \
    test_timeout \
    test_tmpdir \
    test_url

  ztr_path=${ztr_path:-$ZTR_PATH}

  if [[ -z $ztr_path ]] && ! 'builtin' 'command' -v ztr > /dev/null; then
    'builtin' 'printf' "Requires ztr. Load it first, or pass its path as \$ztr_path. See https://zsh-test-runner.olets.dev\n"
    return 1
  fi

  cmd=$1

  # %x is the file being executed; $0 inside a function is just the function name
  job_queue_dir=${${(%):-%x}:A:h}
  if [[ $job_queue_dir =~ "/tests" ]]; then
    job_queue_dir+=/..
  fi

  test_dir=$job_queue_dir/tests

  if [[ ${(%):-%#} == '#' ]]; then
    test_tmpdir=${${TMPDIR:-/tmp}%/}/zsh-job-queue-privileged-users-tests
  else
    test_tmpdir=${${TMPDIR:-/tmp}%/}/zsh-job-queue-tests
  fi

  # Save user configuration
  job_queue_debug_saved=$JOB_QUEUE_DEBUG
  job_queue_privileged_tmpdir_saved=$JOB_QUEUE_PRIVILEGED_TEMPDIR
  job_queue_timeout_saved=$JOB_QUEUE_TIMEOUT_AGE_SECONDS
  job_queue_tmpdir_saved=$JOB_QUEUE_TMPDIR

  # Configure. The tmpdir is read when the plugin is sourced, so set it first
  JOB_QUEUE_DEBUG=0
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=30
  JOB_QUEUE_TMPDIR=$test_tmpdir
  unset JOB_QUEUE_PRIVILEGED_TEMPDIR

  # Set up data
  test_description="zsh-job-queue test job"
  test_scope=zsh_job_queue_test
  test_scope_2=zsh_job_queue_test_2
  test_timeout=1
  test_url=https://example.test/issues

  # Source dependencies. The empty argument is the function name suffix: without
  # it the sourced file would see this function's $1 and rename its functions
  . $job_queue_dir/zsh-job-queue.zsh ''
  [[ -n $ztr_path ]] && . $ztr_path

  # Clear zsh-test-runner summary
  ztr clear-summary

  # Run tests
  if [[ -n $cmd ]]; then
    . $test_dir/_$cmd.ztr.zsh
  else
    for f ($test_dir/_*.ztr.zsh(N.)); do
      printf "File: %s\n" $f
      . $f
      echo -
    done
  fi

  # Remove artifacts
  'command' 'rm' -rf $test_tmpdir

  # Reset
  JOB_QUEUE_DEBUG=$job_queue_debug_saved
  JOB_QUEUE_PRIVILEGED_TEMPDIR=$job_queue_privileged_tmpdir_saved
  JOB_QUEUE_TIMEOUT_AGE_SECONDS=$job_queue_timeout_saved
  JOB_QUEUE_TMPDIR=$job_queue_tmpdir_saved
  . $job_queue_dir/zsh-job-queue.zsh ''

  # Print test suite results
  ztr summary
}

main $@
