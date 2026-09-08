#!/usr/bin/env zsh

# Cross-session job queues manager for zsh
# https://zsh-job-queue.olets.dev
# v3.0.0
# Copyright (c) 2024 Henry Bley-Vroman
#
# Usage:
#
# ```
# id=$(job-queue push <scope> [<job-description> [<support-ticket-url>]])
# # waits for its turn in the <scope> queue
# # do some work
# job-queue pop $id
# ```
#
# Optionally include a suffix argument when sourcing this file
#   source path/to/zsh-job-queue.zsh <suffix>
# The suffix is appended to the names of the file's exported functions.
# This can be used, for instance, to distinguish multiple copies
# of zsh-job-queue.
#
# In .zshrc:
#   source path/to/zsh-job-queue/zsh-job-queue.zsh
# In a plugin which bundles its own (e.g. Git submodule or subtree) copy:
#   source ./zsh-job-queue/zsh-job-queue.zsh __my-plugin
#
# Refer to zsh-abbr for an example of the latter

function _job_queue:init"${1:-}"() { # this quotation mark to fix syntax highlighting "
  zmodload zsh/datetime
  zmodload zsh/system
  zmodload zsh/zselect
  # -F loads only the zf_-prefixed builtins, so the plain mkdir/rm names
  # are left alone for the rest of the user's session
  zmodload -F zsh/files b:zf_mkdir b:zf_rm

  # Log debugging messages?
  typeset -gi JOB_QUEUE_DEBUG=${JOB_QUEUE_DEBUG:-0}

  # How old does a job have to be to be considered timed out?
  typeset -gi JOB_QUEUE_TIMEOUT_AGE_SECONDS=${JOB_QUEUE_TIMEOUT_AGE_SECONDS:-30}

  # Temp dir
  typeset -g JOB_QUEUE_TMPDIR=${${JOB_QUEUE_TMPDIR:-${${TMPDIR:-/tmp}%/}/zsh-job-queue}%/}/
  typeset -g JOB_QUEUE_PRIVILEGED_TEMPDIR=${${JOB_QUEUE_PRIVILEGED_TEMPDIR:-${JOB_QUEUE_TMPDIR:-${${TMPDIR:-/tmp}%/}/zsh-job-queue-privileged-users}}%/}/

  typeset -g _job_queue_tmpdir=$JOB_QUEUE_TMPDIR

  # Temp dir for privileged users
  if [[ ${(%):-%#} == '#' ]]; then
    _job_queue_tmpdir=$JOB_QUEUE_PRIVILEGED_TEMPDIR
  fi
}

function job-queue"${1:-}"() { # this quotation mark to fix syntax highlighting "
  emulate -LR zsh
  # reseed random on the off-chance another fork started from the same pid without
  # intervening $RANDOMs
  RANDOM=$(( RANDOM ^ (EPOCHREALTIME * 1_000_000) ^ sysparams[pid] ))

  {
    # _job_queue:clear
    # gets unfunction'd
    #
    # @param {string} scope
    function _job_queue:clear() {
      emulate -LR zsh

      _job_queue:debugger

      local scope
      scope=$1

      zf_rm -rf $_job_queue_tmpdir${scope}
    }

    # gets unfunction'd
    function _job_queue:debugger() {
      emulate -LR zsh

      (( JOB_QUEUE_DEBUG )) && 'builtin' 'echo' - $funcstack[2]
    }

    # gets unfunction'd
    function _job_queue:help() {
      emulate -LR zsh

      'command' 'man' job-queue 2>/dev/null || 'command' 'man' ${0:A:h}/man/man1/job-queue.1
    }

    # _job_queue:pop
    # gets unfunction'd
    #
    # @param {string} scope
    # @param {string} job_id
    function _job_queue:pop() {
      emulate -LR zsh

      _job_queue:debugger

      local scope
      local job_id

      scope=$1
      job_id=$2

      zf_rm -f $_job_queue_tmpdir${scope}/$job_id &>/dev/null
    }

    # _job_queue:push
    # gets unfunction'd
    #
    # @param {string} scope
    # @param {string} job_id
    # @param {string} job_description
    # @param {string} support_ticket_url
    function _job_queue:push() {
      emulate -LR zsh

      {
        _job_queue:debugger

        local front_of_queue_job_age
        local front_of_queue_job_id
        local front_of_queue_job_path
        local job_description
        local job_id
        local scope
        local support_ticket_url

        _job_queue:generate-id # sets REPLY variable
        job_id=$REPLY

        scope=$1
        job_description=$2
        support_ticket_url=$3

        # gets unfunction'd
        function _job_queue:push:add_job() {
          _job_queue:debugger

          if ! [[ -d $_job_queue_tmpdir${scope} ]]; then
            zf_mkdir -p $_job_queue_tmpdir${scope}
          fi

          'builtin' 'echo' $job_description > $_job_queue_tmpdir${scope}/$job_id
          'builtin' 'echo' $support_ticket_url >> $_job_queue_tmpdir${scope}/$job_id
        }

        # gets unfunction'd
        # sets REPLY
        function _job_queue:push:get_front_of_queue_job_id() {
          # cannot support debug message
          # oldest first; empty if none
          # NB must be an array assignment: scalar assignments do not glob
          local -a front
          front=( $_job_queue_tmpdir${scope}/*(Om[1]N:t) )
          REPLY=$front[1]
        }

        # gets unfunction'd
        function _job_queue:push:handle_timeout() {
          _job_queue:debugger

          local msg
          local -a msg_data
          local msg_description
          local msg_url

          front_of_queue_job_path=$_job_queue_tmpdir${scope}/$front_of_queue_job_id

          msg_data=( ${(f)"$(<$front_of_queue_job_path)"} ) # this quotation mark to improve syntax highlighting "
          msg_description=$msg_data[1]
          msg_url=$msg_data[2]

          'builtin' 'echo' "job-queue: A job added at $(strftime '%T %b %d %Y' ${${front_of_queue_job_id%%-*}%%.*}) has timed out."

          msg="The job was related to \`$scope\`"

          if [[ -n $msg_description ]]; then
            msg+="'s \`$msg_description\`"
          fi

          msg+="."

          'builtin' 'echo' $msg
          'builtin' 'echo' "This could be the result of manually terminating an activity in \`$scope\`."

          if [[ -n $msg_url ]]; then
            'builtin' 'echo' "If you believe it reflects bug in \`$scope\`, please report it at $msg_url"
          fi

          'builtin' 'echo'

          zf_rm -f $front_of_queue_job_path &>/dev/null
        }

        # gets unfunction'd
        function _job_queue:push:wait_turn() {
          # local so the caller's REPLY keeps holding the job id
          local REPLY

          _job_queue:push:get_front_of_queue_job_id
          front_of_queue_job_id=$REPLY

          while [[ $front_of_queue_job_id != $job_id ]]; do
            # our job file is gone, e.g. `job-queue clear $scope` ran while we waited
            [[ $front_of_queue_job_id ]] || break

            front_of_queue_job_age=$(( $EPOCHREALTIME - ${front_of_queue_job_id%%-*} ))

            if (( $front_of_queue_job_age > $JOB_QUEUE_TIMEOUT_AGE_SECONDS )); then
              _job_queue:push:handle_timeout
            fi

            # fork-free sleep, in hundredths of a second
            zselect -t 1

            # keep last: zselect returns 1 on timeout, and the loop takes its status
            _job_queue:push:get_front_of_queue_job_id
            front_of_queue_job_id=$REPLY
          done
        }

        _job_queue:push:add_job
        _job_queue:push:wait_turn
      } always {
        unfunction -m _job_queue:push:add_job
        unfunction -m _job_queue:push:get_front_of_queue_job_id
        unfunction -m _job_queue:push:handle_timeout
        unfunction -m _job_queue:push:wait_turn
      }
    }

    # gets unfunction'd
    function _job_queue:generate-id() {
      emulate -LR zsh

      # cannot support debug message

      local uuid

      # the EPOCHREALTIME prefix and the reseeded RANDOM make this unique enough for a queue id, so no uuidgen fork
      'builtin' 'printf' -v uuid '%04x%04x-%04x-4%03x-%x%03x-%04x%04x%04x' \
        $RANDOM $RANDOM \
        $RANDOM \
        $(( RANDOM % 4096 )) \
        $(( 8 + RANDOM % 4 )) $(( RANDOM % 4096 )) \
        $RANDOM $RANDOM $RANDOM

      REPLY="$EPOCHREALTIME--$uuid"
    }

    # gets unfunction'd
    function _job_queue:version() {
      emulate -LR zsh

      'builtin' 'printf' "zsh-job-queue version %s\n" 3.0.0
    }

    for opt in "$@"; do
      case $opt in
        clear)
            shift
            _job_queue:clear $@
            return
            ;;
        "--help"|\
        help)
          _job_queue:help
          return
          ;;
        "--version"|\
        "-v")
          _job_queue:version
          return
          ;;
        pop)
          shift
          _job_queue:pop $@
          return
          ;;
        push)
          shift
          _job_queue:push $@
          return
          ;;
        *)
          'builtin' 'echo' "job-queue: Invalid option $opt"
          return 1
          ;;
      esac
    done
  } always {
    unfunction -m _job_queue:clear
    unfunction -m _job_queue:debugger
    unfunction -m _job_queue:help
    unfunction -m _job_queue:pop
    unfunction -m _job_queue:push
    unfunction -m _job_queue:generate-id
    unfunction -m _job_queue:version
  }
}

_job_queue:init${1:-}
unfunction -m _job_queue:init${1:-}
