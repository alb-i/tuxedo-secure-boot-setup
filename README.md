(Update: see last paragraph.)

# Setup Secure Boot on Tuxedo-OS (Ubuntu) 20.04 with InsydeH2O bios on a tuxedo-computer linux laptop

This guide is based on [another guide](https://ruderich.org/simon/notes/secure-boot-with-grub-and-signed-linux-and-initrd) and [this guide about how to sign for secure boot](https://ubuntu.com/blog/how-to-sign-things-for-secure-boot), but adapted for my machine.
Why? InsydeH2O-Bios does not allow you to ask for a password whenever something else than the main boot drive is to be booted. You can set a system power on password, in which case you have to enter a password before it boots or goes into firmware setup. If you disable this, everyone can just press F2 and boot an USB stick/network boot image -- so you are at risk of an [evil maid attack](https://github.com/AonCyberLabs/EvilAbigail) that takes a cheap USB drive and approximately 3 minutes to carry out on your laptop.

Make sure that you have set a secure supervisor password in the UEFI firmware, otherwise, this is pretty pointless. Also make sure to not forget this password or you risk bricking your device -- or at least requiring some hardware based interaction.

The overall setup that I found working for me is the following:

* I use my own generated db, KEK, and PK keys and installed them to the firmware using `efi-updatevar`.
* These keys are used to sign the `shim`-loader provided by Ubuntu.
* I generated my own GPG key used for signing the kernel, the initrd-image, and the grub.cfg.
* I generated my own MOK key that is used to sign the kernel and all dkms-kernel modules, this MOK key is added to the keys that the `shim`-loader accepts.
* I generate a custom grub image that is veryfing the GPG signatures (in a detached .sig file) of the kernel, the initrd-image, and the grub.cfg used; this image is signed with both my db and my MOK key. This custom grub image also contains an initial grub.cfg that sets a root password needed to access the console or change the boot options.

The chain of trust is then:
* The firmware verifies the signature of the shim loader, which verifies the signature of the my custom grub-image and provides the facilities to verify the signature of the kernel and all kernel modules.
* The grub image verifies the signature of the boot configuration, the kernel image, and the initrd-image.
* You cannot boot anything else unless you either deactivate secure boot (needs the bios supervisor password), or unless the `shim`-loader accepts it (needs the grub-root password)

Especially you would need at least one of my private keys to modify the boot image, the kernel, or the initrd image.

If you do not like to change the paths in the scripts, copy this repository to `/root/secure_boot`. Also, this is pretty much futile if you have not opted for encrypting your system (and data) drives. Furthermore, note that even with encryption enabled, the `/boot` on my tuxedo-os install is unencrypted. The issue is rather small because someone who cannot boot arbitrary code on your machine would have to extract your system disk in order to mess with your initrd and kernel images, but I still advise you to either encrypt the `/boot`-partition, too -- or at least copy the contents of `/boot` to your encrypted root disk and remove the corresponding entry from `/etc/fstab`.

You might need to install tools on the line, use `sudo apt search ...` to find out, which packages. I guess they are `efibootmgr`, `efitools`, `mokutil`, `shim`, etc.

* To get started: copy this repo to your favorite working directory, `cd` into it, and run
```bash
cp templates/* .
```
for a fresh start.


## Create your private keys

If you want to use unattended updates or the like, then I advise you to not use a passphrase and instead keep all the key files safe! Without such a passphare, if your machine get compromised, then the attacker can sign altered images. If you use passphrases, then you will have to manually run the `./update-all.sh` whenever there are changes to the boot setup (grub.cfg, initrd, kernel).

* The keys used at boot time:
```bash
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=PK/"  -keyout PK.key  -out PK.crt  -days 7300 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=KEK/" -keyout KEK.key -out KEK.crt -days 7300 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=db/"  -keyout db.key  -out db.crt  -days 7300 -nodes -sha256
```

* Edit the `openssl.cnf.template` file and save it as `openssl.cnf`. The key that will be used by the `shim`-loader:
```bash
openssl req -config ./openssl.cnf \
        -new -x509 -newkey rsa:2048 \
        -nodes -days 36500 -outform DER \
        -keyout "MOK.priv" \
        -out "MOK.der"
```

* The key that will be used by the standalone `grub`-loader:
```bash
gpg --gen-key --homedir .
```

## Prepare the keys for installation to the firmware

```bash
cert-to-efi-sig-list PK.crt PK.esl
sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth

cert-to-efi-sig-list KEK.crt KEK.esl
sign-efi-sig-list -k PK.key -c PK.crt KEK KEK.esl KEK.auth

cert-to-efi-sig-list db.crt db.esl
sign-efi-sig-list -k KEK.key -c KEK.crt db db.esl db.auth
```

## Convert the MOK key to be used for signing

```bash
openssl x509 -in MOK.der -inform DER -outform PEM -out MOK.pem
```

## Prepare the keys for installation to the shim loader

* The following code adds a request to add the private MOK key to the `shim`-loader util.
```bash
sudo mokutil --import MOK.der
```
You will be asked to set a password, which you will need later on to actually add the key the next time the shim loader runs. Using your own MOK with the shim loader is explained in detail [in this guide here](https://ubuntu.com/blog/how-to-sign-things-for-secure-boot).


## Set the grub command line root password

* You should replace the string `grub.pbkdf2.sha512.10000.TODO` in `grub-initial.cfg` with what is comes after `PBKDF2 hash of your password is ` in the output of
```bash
grub-mkpasswd-pbkdf2
```
Clearly, you should try to remember that password.

## Set the UUID of the EFI boot partition

* You have to replace the string `UUID.TODO` in `grub-initial.cfg` with the UUID of your `/boot/efi` partition. Use
```bash
cat /etc/fstab | grep /boot/efi
```
to find it. Since this partition is vfat, it should be in the format `NNNN-NNNN`.

## Setup update scripts after changes to initrd or kernel-updates

* Some of the directories might be missing, so first we create these directories:
```bash
sudo mkdir -p /etc/kernel/postrm.d
sudo mkdir -p /etc/kernel/postrm.d
sudo mkdir -p /etc/initramfs/post-update.d
```

* Take a look at `zzzz-sign-boot` and change it to reflect the directory where your `update-all.sh` (along with all the other files) lives.

* Copy the hook that runs `update-all.sh` after changes to the kernel or initramfs:
```bash
sudo cp zzzz-sign-boot /etc/kernel/postrm.d
sudo cp zzzz-sign-boot /etc/kernel/postrm.d
sudo cp zzzz-sign-boot /etc/initramfs/post-update.d
```

## Try to build the images now

* Make sure you installed `shim` via
```bash
sudo apt install shim
```


* Now, run
```bash
./update-all.sh
```
for the first time. __If you see errors then I advice you to fix them before continuing with the next section.__

Also, you might want to run this command (it is only needed once, and really not that much needed at all).
```bash
sudo cp /boot/grub/fonts/unicode.pf2 /boot/efi/unicode.pf2
```

## Add the shim loader to the firmware boot options

* By now, if you do
```bash
ls -lh /boot/efi
```
you should see something like this
```
total 131M
-rwxr-xr-x 1 root root 1.8K Oct  9 14:53 boot.key
-rwxr-xr-x 1 root root  438 Oct  9 14:53 boot.key.sig
drwxr-xr-x 5 root root 4.0K Oct  3 21:10 EFI
-rwxr-xr-x 1 root root 1.2M Oct  9 14:53 fbx64.efi
-rwxr-xr-x 1 root root 1.3K Oct  9 14:53 grub.cfg
-rwxr-xr-x 1 root root  438 Oct  9 14:53 grub.cfg.sig
-rwxr-xr-x 1 root root 6.1M Oct  9 14:53 grubx64.efi
-rwxr-xr-x 1 root root 102M Oct  9 14:54 initrd.img-5.4.0-42-generic
-rwxr-xr-x 1 root root  438 Oct  9 14:54 initrd.img-5.4.0-42-generic.sig
-rwxr-xr-x 1 root root 1.3M Oct  9 14:54 mmx64.efi
-rwxr-xr-x 1 root root 6.3M Oct  4 10:10 secure-bootx64.efi
-rwxr-xr-x 1 root root 1.3M Oct  9 14:54 shimx64.efi
-rwxr-xr-x 1 root root 2.3M Oct  3 21:38 unicode.pf2
-rwxr-xr-x 1 root root  12M Oct  9 14:54 vmlinuz-5.4.0-42-generic
-rwxr-xr-x 1 root root  438 Oct  9 14:54 vmlinuz-5.4.0-42-generic.sig
```
__If you do not see these (or similar) files, I advice you again to fix this before continuing with the next section.__

* The next step really depends on the hardware internals of your machine, the quickest way to figure out the correct settings is to run
```bash
efibootmgr -v
```
to see the current boot entries as seen by the firmware. After setting up secure boot, mine looks like this:

```
BootCurrent: 0002
Timeout: 0 seconds
BootOrder: 0002,0000,2001,2002,2003
Boot0000  ubuntu	HD(2,GPT,ff003d56-4215-49c8-9855-4154c468007d,0x100800,0x100000)/File(\EFI\ubuntu\grubx64.efi)RC
Boot0001  ubuntu	HD(2,GPT,ff003d56-4215-49c8-9855-4154c468007d,0x100800,0x100000)/File(\EFI\ubuntu\grubx64.efi)
Boot0002* shim	HD(2,GPT,ff003d56-4215-49c8-9855-4154c468007d,0x100800,0x100000)/File(shimx64.efi)
Boot2001* EFI USB Device	RC
Boot2002* EFI DVD/CDROM	RC
Boot2003* EFI Network	RC
```
The code `RC` means that it has been created by the firmware at some point in time. The entry `Boot0002` corresponds to the shim loader that I added. You might want to inspect your current boot loader, especially the number after `HD(`. It turns out that drive numbering at boot time is not the same as when using the OS.

* To add the `shim` loader boot option, I used the command
```bash
sudo efibootmgr -c --disk /dev/nvme0n1 -p2 -L "shim" -l \shimx64.efi
```
Here, the `-p2` is crucial, because without this parameter, `efibootmgr` will add the entry as `HD(1,....)`. Of course, the firmware does not find the entry because of this and removes it on the next power up (it won't even show up in the menu making you believe that the change was not stored in the firmware, but it was). You might need to change the number in this parameter to reflect the output of the above command.

* Reboot your system, the shim loader should start in management mode and ask you for your password in order to add your MOK key.

__If everything works up to here and you were able to boot through the shim loader and the standalone grub image, it's time to get ready to enforce secure boot__

## Install your firmware keys to EFI

* Just to be safe, run this:
```bash
chattr -i /sys/firmware/efi/efivars/{PK,KEK,db,dbx}-*
``` 

* And to install the keys, run in this order:
```bash
sudo efi-updatevar -f db.auth db
sudo efi-updatevar -f KEK.auth KEK
sudo efi-updatevar -f PK.auth PK
```
In order for this code to work, you have to delete the PK-key from within the firmware setup if such a key is set. This switches the firmware to setup-mode and allows to add new KEK and db keys. After this is done, adding a PK-key then changes the firmware back to user mode (where you cannot change anything without the PK-authorization).

* Make sure that your firmware is set to enforce secure boot, especially if you manually disabled this during debugging of your setup!


# Update: it seems to work fine

I now can confirm that the update script does its jobs, namely signing the modules after a kernel update as well as removing unused kernels/initrd-images from the efi drive once they got wiped from /boot.
I also discovered that ubuntu adds its own unsigned bootloader on some update occasions back to the firmware and makes it the default option. Clearly, this won't boot as it is not signed by the machine key. It will give an error message and then boot the signed grub afterwards - which is a waste of startup time. I solved this by adding
```bash
efibootmgr -o 0002
```
to the `update-all.sh` script. The number after `-o` may vary for you, when you run `efibootmgr` you see your options.
