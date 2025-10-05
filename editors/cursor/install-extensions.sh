#!/bin/bash
# A script to install Cursor extensions from extensions.list

cat "$(dirname "$0")/cursor/extensions.list" | while read extension || [[ -n $extension ]];
do
  cursor --install-extension $extension
done
