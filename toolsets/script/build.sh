# Any project the recipe says how to build: BUILD (a shell command, run in the
# project on the builder) on a builder of kind BUILDER, and ARTIFACTS (globs,
# relative to the project) for what comes back. Runs on the builder in its
# workspace ($W), appended to the job's variables by farm/build.sh.
set -e -o pipefail
cd "$W/$GAME"
[ -n "$BUILD_B64" ] || { echo "script: the recipe has no BUILD" >&2; exit 2; }
/usr/bin/time -f "build wall %e s" bash -e -o pipefail -c "$(echo "$BUILD_B64" | base64 -d)"
[ -n "$ARTIFACTS" ] || { echo "script: the recipe has no ARTIFACTS" >&2; exit 2; }
ls -d $ARTIFACTS | sed "s|^|$GAME/|" > "$W/.artifacts-$JOB"
