#!/bin/sh
# scripts/check-pins.sh: the version matrix of this repository, and its consistency.
#
# Prints the commit pinned for each submodule (the table of README.md) and fails when the
# orchestration pins another harness commit (its AIProver/ submodule) than harness/.
# Run it after bumping a submodule pointer, before the commit.
set -eu
cd "$(dirname "$0")/.."

# describe PATH: the commit and commit date of a submodule's checkout.
describe() {
  # shellcheck disable=SC2016  # literal backquotes of the Markdown table
  printf '| %s | `%s` | %s |\n' "$1" "$(git -C "$1" rev-parse --short=7 HEAD)" \
    "$(git -C "$1" log -1 --format=%cs HEAD)"
}

printf '| component | commit | date |\n|---|---|---|\n'
for path in $(git config -f .gitmodules --get-regexp 'submodule\..*\.path' | awk '{ print $2 }'); do
  describe "$path"
done

harness=$(git -C harness rev-parse HEAD)
expected=$(git -C orchestration ls-tree HEAD AIProver | awk '{ print $3 }')
if [ "$harness" != "$expected" ]; then
  printf '\nmismatch: harness/ is at %s, orchestration pins AIProver/ at %s\n' \
    "$harness" "$expected" >&2
  exit 1
fi
