#!/bin/bash
pacstrap /mnt base base-devel
genfstab -P /mnt > /mnt/etc/fstab

# grab other script to execute in the chroot
wget https://raw.githubusercontent.com/demon012/archinstall/master/install-main.sh -O /mnt/install.sh
chmod +x /mnt/install.sh

# execute the script in the chroot
arch-chroot /mnt /mnt/install.sh
