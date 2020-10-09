#!/bin/sh

cd $(dirname $0)

set +x
set -eu

GPG_KEY=$(gpg --homedir . --list-keys | grep 'pub\b' -A 1 | tail -n 1 | awk '{ print $1 }')
BOOT_DIRECTORY='/boot'      # source, no trailing /
EFI_DIRECTORY='./efi'   # target, no trailing /
KERNEL_PREFIX='vmlinuz-'
INITRD_PREFIX='initrd.img-'

mkdir -p $EFI_DIRECTORY

escape_for_sed() {
    printf '%s' "$1" | sed 's!/!\\/!g'
}

rm -rf tmp
mkdir tmp

TMP_GRUB_CFG=tmp/grub.cfg
TMP_KERNELS=tmp/kernels
TMP_KEY=tmp/boot.key

gpg --homedir . --export > $TMP_KEY

: >"$TMP_KERNELS"
for x in "$BOOT_DIRECTORY/$KERNEL_PREFIX"*; do
    printf '%s\n' "$x" >>"$TMP_KERNELS"
done

# Newest kernel first.
cat grub.cfg.head >"$TMP_GRUB_CFG"
sort --reverse --version-sort "$TMP_KERNELS" | while read vmlinuz; do
    vmlinuz="${vmlinuz##$BOOT_DIRECTORY/}"
    version="${vmlinuz##$KERNEL_PREFIX}"
    initrd="${INITRD_PREFIX}${version}"

    vmlinuz="$(escape_for_sed "$vmlinuz")"
    version="$(escape_for_sed "$version")"
    initrd="$(escape_for_sed "$initrd")"

    sed -e "s/VERSION/$version/g" \
        -e "s/VMLINUZ/$vmlinuz/g" \
        -e "s/INITRD/$initrd/g" \
        <grub.cfg.menu \
        >>"$TMP_GRUB_CFG"
done
cat grub.cfg.tail >>"$TMP_GRUB_CFG"

for x in "$TMP_GRUB_CFG" "$TMP_KEY" "$BOOT_DIRECTORY/$INITRD_PREFIX"* ; do
    name="$(basename "$x")"

    echo "signing and copying '$x' to '$EFI_DIRECTORY'"
    sudo cp "$x" "$EFI_DIRECTORY"
    sudo rm -f "$EFI_DIRECTORY/$name.sig"
    sudo gpg --homedir . --default-key "$GPG_KEY" --detach-sign "$EFI_DIRECTORY/$name"
done
for x in "$BOOT_DIRECTORY/$KERNEL_PREFIX"* ; do
    name="$(basename "$x")"

    echo "MOK signing and then gpg-signing '$x' to '$EFI_DIRECTORY'"
    sudo sbsign --key MOK.priv --cert MOK.pem "$x" --output "$EFI_DIRECTORY/$name"
    sudo rm -f "$EFI_DIRECTORY/$name.sig"
    sudo gpg --homedir . --default-key "$GPG_KEY" --detach-sign "$EFI_DIRECTORY/$name"

    echo "Signing modules..."
    for y in "/lib/modules/${name#vmlinuz-}/updates/dkms/"*.ko ; do
        echo "signing $y"
        sudo kmodsign sha512 MOK.priv MOK.der $y
    done
done

rm -r tmp
