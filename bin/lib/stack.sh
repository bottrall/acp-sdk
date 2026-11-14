# shellcheck shell=bash
# Sourced by the bin/ scripts: finds the repo's stacks (a root Gemfile is Ruby,
# a root package.json is TS), splits arguments between them, and runs each
# selected stack even when an earlier one failed.
#
# Written for bash 3.2 as well as 5, so empty arrays expand as
# ${array[@]+"${array[@]}"}: 3.2 treats a bare "${array[@]}" of an empty array
# as unbound under `set -u`.

SCRIPT="bin/$(basename "$0")"

# A usage error: the arguments can't be run as given.
fail() {
  echo "$SCRIPT: $*" >&2
  exit 2
}

# The script doesn't apply to this repo. It succeeds, so bin/ci can list a
# script in every repo it applies to without breaking the others.
not_applicable() {
  echo "$SCRIPT: $*; nothing to do"
  exit 0
}

# A stack the script doesn't apply to, in a run that goes on to the next one.
skip_stack() {
  echo "$SCRIPT: $*; skipping"
}

has_ruby() { [[ -f Gemfile ]]; }
has_ts() { [[ -f package.json ]]; }
has_vite_config() { compgen -G 'vite.config.*' >/dev/null; }

# `rake -T` lists only tasks with a description; `rake -P` lists every task.
# The list is captured before grepping it: `grep -q` exits on the first match,
# and under pipefail the rake it cut off would turn a match into a failure.
has_rake_task() {
  local tasks
  tasks=$(bundle exec rake -P 2>/dev/null) || return 1
  grep -qx "rake $1" <<<"$tasks"
}

# parse_args paths|no-paths [value flags...] -- [arguments...]
#
# Sets ONLY (ruby, ts or empty), PATHS and FLAGS. `--only=` picks the stack.
# With `paths`, a bare argument is a path, unless it follows one of the value
# flags, which take the next argument as their value; any other flag's value
# must be joined to it with `=`. With `no-paths`, every argument is a runner
# flag or flag value.
parse_args() {
  local mode=$1 value_flags=" "
  shift
  while [[ $1 != -- ]]; do
    value_flags+="$1 "
    shift
  done
  shift

  ONLY=""
  PATHS=()
  FLAGS=()
  while (($#)); do
    case $1 in
      --only=ruby | --only=ts) ONLY=${1#--only=} ;;
      --only=*) fail "--only takes ruby or ts, not '${1#--only=}'" ;;
      -*)
        FLAGS+=("$1")
        if [[ $value_flags == *" $1 "* ]] && (($# > 1)); then
          FLAGS+=("$2")
          shift
        fi
        ;;
      *)
        if [[ $mode == paths ]]; then
          PATHS+=("$1")
        else
          FLAGS+=("$1")
        fi
        ;;
    esac
    shift
  done
}

# select_stacks [router]
#
# Sets STACKS (Ruby first) from --only, the stacks the repo has, and the paths
# given, and splits PATHS into RUBY_PATHS and TS_PATHS. In a mixed repo the
# router (a function printing ruby or ts for a path, or failing) sends each
# path to its stack, and only stacks that got a path run. Runner flags need
# exactly one stack, since each runner takes different ones.
select_stacks() {
  local router=${1:-} path stack
  STACKS=()
  RUBY_PATHS=()
  TS_PATHS=()

  if ! has_ruby && ! has_ts; then
    not_applicable "no Gemfile or package.json"
  fi

  if [[ -n $ONLY ]]; then
    require_stack "$ONLY"
    STACKS=("$ONLY")
  elif has_ruby && has_ts && ((${#PATHS[@]})); then
    for path in "${PATHS[@]}"; do
      stack=$("$router" "$path") ||
        fail "can't tell whether $path is Ruby or TS; pass --only=ruby or --only=ts"
      if [[ $stack == ruby ]]; then RUBY_PATHS+=("$path"); else TS_PATHS+=("$path"); fi
    done
    if ((${#RUBY_PATHS[@]})); then STACKS+=(ruby); fi
    if ((${#TS_PATHS[@]})); then STACKS+=(ts); fi
  elif has_ruby && has_ts; then
    STACKS=(ruby ts)
  elif has_ruby; then
    STACKS=(ruby)
  else
    STACKS=(ts)
  fi

  # A single stack takes every path, routed or not.
  if ((${#STACKS[@]} == 1)) && ((${#PATHS[@]})); then
    if [[ ${STACKS[0]} == ruby ]]; then RUBY_PATHS=("${PATHS[@]}"); else TS_PATHS=("${PATHS[@]}"); fi
  fi

  if ((${#FLAGS[@]})) && ((${#STACKS[@]} != 1)); then
    fail "${FLAGS[*]} can only go to one stack's runner; pass --only=ruby or --only=ts"
  fi
}

require_stack() {
  case $1 in
    ruby) has_ruby || fail "--only=ruby, but there's no Gemfile" ;;
    ts) has_ts || fail "--only=ts, but there's no package.json" ;;
  esac
}

# run_stacks stack...
#
# Runs run_ruby / run_ts (defined by the script) for each stack in turn. Every
# stack runs even if one before it failed; the result is the last failure's
# exit status, or 0. Each runs in a subshell with `set -e`: a function called
# as an `if` or `||` condition would silently run with `set -e` off.
run_stacks() {
  local stack code status=0
  for stack in "$@"; do
    if (($# > 1)); then echo "$SCRIPT: $stack" >&2; fi
    set +e
    (
      set -e
      "run_$stack"
    )
    code=$?
    set -e
    if ((code != 0)); then
      echo "$SCRIPT: $stack failed (exit $code)" >&2
      status=$code
    fi
  done
  return "$status"
}
