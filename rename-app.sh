#!/usr/bin/env bash
# Rename the template app.
#
# Usage: ./rename-app.sh <AppName> <bundle.id>
# Example: ./rename-app.sh CoffeeLog com.jane.CoffeeLog
#
# Updates Package.swift, xtool.yml, Sources/<AppName>/ and the @main App struct.
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <AppName> <bundle.id>" >&2
  exit 1
fi

new_name=$1
bundle_id=$2

cd "$(dirname "$0")"

# The name becomes a Swift module and type name, so it must be a valid identifier.
if ! [[ $new_name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "error: app name must start with a letter or _ and contain only letters, digits and _" >&2
  exit 1
fi
if ! [[ $bundle_id =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "error: bundle ID must look like com.example.MyApp" >&2
  exit 1
fi

old_name=$(awk -F': *' '$1 == "product" { print $2 }' xtool.yml | tr -d "\"' \r")
if [ -z "$old_name" ]; then
  echo "error: could not read 'product:' from xtool.yml" >&2
  exit 1
fi
if [ ! -d "Sources/$old_name" ]; then
  echo "error: Sources/$old_name not found" >&2
  exit 1
fi

if [ "$new_name" != "$old_name" ]; then
  if [ -e "Sources/$new_name" ]; then
    echo "error: Sources/$new_name already exists" >&2
    exit 1
  fi

  # Package.swift: package, product and target names are all "<old_name>".
  OLD=$old_name NEW=$new_name perl -pi -e 's/"\Q$ENV{OLD}\E"/"$ENV{NEW}"/g' Package.swift

  mv "Sources/$old_name" "Sources/$new_name"
  if [ -f "Sources/$new_name/${old_name}App.swift" ]; then
    mv "Sources/$new_name/${old_name}App.swift" "Sources/$new_name/${new_name}App.swift"
  fi
  OLD=$old_name NEW=$new_name perl -pi -e 's/\bstruct \Q$ENV{OLD}\EApp\b/struct $ENV{NEW}App/' \
    "Sources/$new_name"/*.swift
fi

NEW=$new_name BID=$bundle_id perl -pi -e '
  s/^product:.*/product: $ENV{NEW}/;
  s/^bundleID:.*/bundleID: $ENV{BID}/;
' xtool.yml

echo "Renamed $old_name -> $new_name (bundle ID $bundle_id)"
