#!/bin/sh

cd $(dirname $0)

set +x
set -eu

GPG_KEY=$(gpg --homedir . --list-keys | grep 'pub\b' -A 1 | tail -n 1 | awk '{ print $1 }')
TARGET_DIR='./efi'
SECUREBOOT_DB_KEY='./db.key'
SECUREBOOT_DB_CRT='./db.crt'

mkdir -p efi

mkdir -p tmp

TMP_EFI='tmp/signed.efi'


for x in /usr/lib/shim/*.efi "$TARGET_DIR/grubx64.efi" ; do

xnodir=$(basename $x)

sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_EFI" "$x"

echo "writing signed $x to '$TARGET_DIR/$xnodir'"

cp "$TMP_EFI" "$TARGET_DIR/$xnodir"

done

rm -r tmp
