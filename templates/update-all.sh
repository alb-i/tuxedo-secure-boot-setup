#!/bin/sh

cd $(dirname $0)

rm -Rf efi
mkdir -p efi

./create-initial-grub-efi.sh
./sign-and-copy-shim.sh
./sign-kernels-and-create-grub-cfg.sh

for x in /boot/efi/vmlinuz-* /boot/efi/initrd.img-* ; do
    name0="${x%.sig}"

    if [ -e "/boot${name0#/boot/efi}" ] ; then
        echo "Keeping $x <-- still used."
    else
        echo "Removing old file $x"
        sudo rm "$x"
    fi
done

sudo cp efi/* /boot/efi
