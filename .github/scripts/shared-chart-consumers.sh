#!/usr/bin/env bash
#
# A package embeds a local chart by relative path (`path: ../../../charts/x`),
# so changing that chart changes the package's artifact. release-please assigns
# commits to packages by directory, and charts/ is outside every package, so a
# charts-only change would release nothing and never reach the registry.
#
# This fails the build when a shared chart moves without its consumers.
#
# Usage: shared-chart-consumers.sh <changed-file>...
set -uo pipefail

changed=("$@")
status=0

# Nothing to inspect (empty diff): succeed rather than trip `set -u`.
[[ ${#changed[@]} -eq 0 ]] && exit 0

changed_under() {           # changed_under <dir>
  local dir="$1" f
  for f in "${changed[@]}"; do
    [[ "$f" == "$dir/"* ]] && return 0
  done
  return 1
}

# Which shared charts were touched?
charts=$(printf '%s\n' "${changed[@]}" | grep -oE '^charts/[^/]+' | sort -u)

for chart in ${charts}
do
  name="${chart#charts/}"
  # Packages embedding this chart by relative path
  consumers=$(grep -rl "path: .*charts/${name}\$" packages/ 2>/dev/null | xargs -r -n1 dirname | sort -u)

  [[ -z "${consumers}" ]] && continue

  for pkg in ${consumers}
  do
    if changed_under "${pkg}"; then
      echo "ok   ${chart} changed, and so did ${pkg}"
    else
      echo "::error title=Shared chart changed without its consumer::${chart} is embedded by ${pkg}, but nothing under ${pkg} changed. release-please assigns commits by directory, so ${pkg} would not be released and the change would never be published. Bump or touch ${pkg} in this pull request."
      status=1
    fi
  done
done

exit ${status}
