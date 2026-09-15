#!/bin/sh
# toysize -- toy unit conversions (antz benchmark fixture).
set -u

if [ "$#" -ne 2 ]; then
  echo "usage: sh toysize.sh cm-to-inch <centimeters>" >&2
  exit 2
fi

case "$1" in
  cm-to-inch)
    awk -v n="$2" 'BEGIN { printf "%.6f\n", n / 2.54 }'
    ;;
  *)
    echo "toysize: unknown conversion: $1" >&2
    exit 2
    ;;
esac
