#!/bin/sh

# Helper for PackageUpdatesService.qml: how many package updates are waiting
# on a Fedora system.
#
#   pkg-updates.sh check <flatpak: 1|0>
#
# Prints, one per line:
#   status=ok|nocmd|error        nocmd = `dnf` is missing
#   repo=<n>                     updates from the dnf repositories
#   aur=<n>                      updates from Flatpak (if installed and asked for)
#   pkg=<name> <old> -> <new>    the first 40 repository updates
#   aurpkg=<name> <old> -> <new> the first 20 Flatpak updates
#
# `dnf check-update` needs no root. Its exit codes are 100 (updates),
# 0 (none) and 1 (error). Lines look like "name.arch  version  repo".

mode="$1"
want_aur="${2:-0}"

case "$mode" in
    check)
        if ! command -v dnf >/dev/null 2>&1; then
            echo "status=nocmd"
            exit 0
        fi
        out=$(dnf -q check-update 2>/dev/null)
        rc=$?
        case "$rc" in
            0|100) out=$(printf '%s\n' "$out" | awk 'NF == 3 && $1 ~ /\./ { n = $1; sub(/\.[^.]*$/, "", n); if (!seen[n]++) print }')
                   repo=$(printf '%s\n' "$out" | grep -c .) ;;
            *) echo "status=error"; exit 0 ;;
        esac
        aur=0
        aurout=""
        if [ "$want_aur" = "1" ] && command -v flatpak >/dev/null 2>&1; then
            aurout=$(flatpak remote-ls --updates --columns=application,version 2>/dev/null)
            [ -n "$aurout" ] && aur=$(printf '%s\n' "$aurout" | grep -c .)
        fi
        echo "status=ok"
        echo "repo=$repo"
        echo "aur=$aur"
        [ -n "$out" ] && printf '%s\n' "$out" | head -n 40 | while read -r na new _; do
            name=${na%.*}
            old=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "$name" 2>/dev/null | tail -n 1)
            echo "pkg=$name ${old:-?} -> $new"
        done
        [ -n "$aurout" ] && printf '%s\n' "$aurout" | head -n 20 | awk -F '\t' '{ print "aurpkg=" $1 " ? -> " ($2 == "" ? "new" : $2) }'
        exit 0
        ;;
    *)
        echo "usage: $0 check <flatpak 1|0>" >&2
        exit 2
        ;;
esac
