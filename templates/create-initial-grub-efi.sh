#!/bin/sh

cd $(dirname $0)

set +x
set -eu

GPG_KEY=$(gpg --homedir . --list-keys | grep 'pub\b' -A 1 | tail -n 1 | awk '{ print $1 }')
TARGET_EFI='./efi/grubx64.efi'
SECUREBOOT_DB_KEY='./db.key'
SECUREBOOT_DB_CRT='./db.crt'

mkdir -p efi

# GRUB doesn't allow loading new modules from disk when secure boot is in
# effect, therefore pre-load the required modules.
MODULES=
MODULES="$MODULES part_gpt fat ext2 exfat"           # partition and file systems for EFI
MODULES="$MODULES gzio lvm cbfs"                     
MODULES="$MODULES gettext gfxterm cat help"             
MODULES="$MODULES ls lsefi halt efifwsetup efi_gop efi_uga efinet"             
MODULES="$MODULES configfile"                  # source command
MODULES="$MODULES verifiers gcry_sha512 gcry_rsa crypto cryptodisk" # signature verification
#MODULES="$MODULES gcry_arcfour gcry_blowfish gcry_camellia gcry_cast5 gcry_crc gcry_des gcry_dsa gcry_idea gcry_md4 gcry_md5 gcry_rfc2268 gcry_rijndael gcry_rmd160 gcry_rsa gcry_seed gcry_serpent gcry_sha1 gcry_sha256 gcry_sha512 gcry_tiger gcry_twofish gcry_whirlpool pgp" # all the crypto stuff available
MODULES="$MODULES password_pbkdf2"             # hashed password
MODULES="$MODULES echo normal linux linuxefi"  # boot linux
MODULES="$MODULES all_video"                   # video output
MODULES="$MODULES search search_fs_uuid search_fs_file search_label signature_test"       # search --fs-uuid
MODULES="$MODULES reboot sleep"                # sleep, reboot
#MODULES="$MODULES acpi adler32 affs afs ahci all_video aout appleldr archelp ata at_keyboard backtrace bfs bitmap bitmap_scale blocklist boot bsd bswap_test btrfs bufio cat cbfs cbls cbmemc cbtable cbtime chain cmdline_cat_test cmp cmp_test configfile cpio_be cpio cpuid crc64 cryptodisk crypto cs5536 ctz_test datehook date datetime diskfilter disk div div_test dm_nv echo efifwsetup efi_gop efinet efi_uga ehci elf eval exfat exfctest ext2 extcmd f2fs fat file fixvideo font fshelp functional_test gcry_arcfour gcry_blowfish gcry_camellia gcry_cast5 gcry_crc gcry_des gcry_dsa gcry_idea gcry_md4 gcry_md5 gcry_rfc2268 gcry_rijndael gcry_rmd160 gcry_rsa gcry_seed gcry_serpent gcry_sha1 gcry_sha256 gcry_sha512 gcry_tiger gcry_twofish gcry_whirlpool geli gettext gfxmenu gfxterm_background gfxterm_menu gfxterm gptsync gzio halt hashsum hdparm hello help hexdump hfs hfspluscomp hfsplus http iorw iso9660 jfs jpeg keylayouts keystatus ldm legacycfg legacy_password_test linux16 linuxefi linux loadbios loadenv loopback lsacpi lsefimmap lsefi lsefisystab lsmmap ls lspci lssal luks lvm lzopio macbless macho mdraid09_be mdraid09 mdraid1x memdisk memrw minicmd minix2_be minix2 minix3_be minix3 minix_be minix mmap morse mpi msdospart mul_test multiboot2 multiboot nativedisk net newc nilfs2 normal ntfscomp ntfs odc offsetio ohci part_acorn part_amiga part_apple part_bsd part_dfly part_dvh part_gpt part_msdos part_plan part_sun part_sunpc parttool password password_pbkdf2 pata pbkdf2 pbkdf2_test pcidump pgp play png priority_queue probe procfs progress raid5rec raid6rec random rdmsr read reboot regexp reiserfs relocator romfs scsi search_fs_file search_fs_uuid search_label search serial setjmp setjmp_test setpci sfs shift_test shim_lock signature_test sleep sleep_test smbios squash4 strtoull_test syslinuxcfg tar terminal terminfo test_blockarg testload test testspeed tftp tga time tpm trig tr true udf ufs1_be ufs1 ufs2 uhci usb_keyboard usb usbms usbserial_common usbserial_ftdi usbserial_pl2303 usbserial_usbdebug usbtest verifiers video_bochs video_cirrus video_colors video_fb videoinfo video videotest_checksum videotest wrmsr xfs xnu xnu_uuid xnu_uuid_test xzio zfscrypt zfsinfo zfs zstd" # this is everything that was in my boot partition

rm -rf tmp
mkdir -p tmp

TMP_GPG_KEY='tmp/gpg.key'
TMP_GRUB_CFG='tmp/grub-initial.cfg'
TMP_GRUB_SIG="$TMP_GRUB_CFG.sig"
TMP_GRUB_EFI='tmp/grubx64.efi'

gpg --homedir . --export "$GPG_KEY" >"$TMP_GPG_KEY"

cp grub-initial.cfg "$TMP_GRUB_CFG"
rm -f "$TMP_GRUB_SIG"
gpg --homedir . --default-key "$GPG_KEY" --detach-sign "$TMP_GRUB_CFG"

grub-mkstandalone \
    --directory /usr/lib/grub/x86_64-efi \
    --format x86_64-efi \
    --modules "$MODULES" \
    --pubkey "$TMP_GPG_KEY" \
    --output "$TMP_GRUB_EFI" \
    "boot/grub/grub.cfg=$TMP_GRUB_CFG" \
    "boot/grub/grub.cfg.sig=$TMP_GRUB_SIG"

sbsign --key "$SECUREBOOT_DB_KEY" --cert "$SECUREBOOT_DB_CRT" \
    --output "$TMP_GRUB_EFI" "$TMP_GRUB_EFI"

echo "writing signed grub.efi to '$TARGET_EFI'"
cp "$TMP_GRUB_EFI" "$TARGET_EFI"

rm -r tmp
