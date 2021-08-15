#!/bin/bash
## stage 1 ##
# enable multilib
# ex - /etc/pacman.conf << end-of-script
# 93
# s/#//
# +
# s/#//
# wq
# end-of-script

set -euo pipefail
IFS=$'\n\t'

get_partitions() # {{{
{
    local DISKNAME="$1"

    NUM_DISKS=$(lsblk -J | jq  '.[] | length')
    for CUR_DISK in $(seq 0 $((NUM_DISKS - 1)));
    do
        if [ $(lsblk -J | jq -r ".[][$CUR_DISK].name") == "$DISKNAME" ];
        then
            DISK_CHILDREN=$(lsblk -J | jq -r ".[][$CUR_DISK].children")
            break
        fi
    done
} #}}}
get_partition() # {{{
{
    local CHILD_NUM="$1"
    PART_NAME=$(echo "$DISK_CHILDREN" | jq -r ".[$CHILD_NUM].name")
} # }}}
chroot_command() # {{{
{
    COMMAND="arch-chroot /mnt $1"
    echo "Running: $COMMAND"
    eval $COMMAND
} # }}}
install_deps() # {{{
{
    pacman -Sy --noconfirm jq lvm2 btrfs-progs dialog
} # }}}
select_install_disk() # {{{
{
    NUM_DISKS=$(lsblk -J | jq  '.[] | length')
    DISKS=""
    for CUR_DISK in $(seq 0 $((NUM_DISKS - 1)));
    do
        if [ "$(lsblk -J | jq -r ".[][$CUR_DISK].type")" == "disk" ];
        then
            DISK_NAME=$(lsblk -J | jq -r ".[][$CUR_DISK].name")
            DISK_SIZE=$(lsblk -J | jq -r ".[][$CUR_DISK].size")
            DISKS="${DISKS}${DISK_NAME} ${DISK_SIZE} "
        fi
    done

    COMMAND="$(command -v dialog) --stdout --menu \"Choose the disk to install to (all data will be destroyed on the selected disk):\" 80 80 70 ${DISKS}"
    if ! SEL_DISK=$(eval $COMMAND)
    then
        clear
        echo "OK aborting installation as no disk selected."
        exit
    fi
    COMMAND="$(command -v dialog) --clear"
    eval $COMMAND
    COMMAND="$(command -v dialog) --yesno \"Are you sure you want to wipe ${SEL_DISK} and install Arch Linux?\" 5 80"
    echo "$COMMAND"

    if ! eval $COMMAND
    then
        clear
        echo "OK not installing to ${SEL_DISK}. Exiting..."
        exit 1
    else
        unset COMMAND
        unset DISK_NAME
        unset DISKS

        DISK="$SEL_DISK"
        DISK_PATH="/dev/$SEL_DISK"

        unset SEL_DISK
        dialog --clear
    fi
} # }}}
get_encryption_password() # {{{
{
    local COMMAND="dialog --stdout --passwordbox \"Please enter the password to use for disk encryption\" 8 50"
    ENCRPYTION_PASS="$(eval $COMMAND)"
    dialog --clear
} # }}}
get_required_hostname() # {{{
{
    local COMMAND="dialog --stdout --inputbox \"Please enter the hostname you want to use for the system.\" 8 50"
    REQUIRED_HOSTNAME="$(eval $COMMAND)"
    dialog --clear
} # }}}
wipe_disk() # {{{
{
    echo "Wiping disk"
    wipefs -a "$DISK_PATH"
}
# }}}
partition_disk() # {{{
{
    echo "Partitioning disk: $DISK_PATH"
    # Setup EFI and boot
    parted -s "$DISK_PATH" "mklabel gpt"
    parted -s "$DISK_PATH" "mkpart esp fat32 1M 1G"
    parted -s "$DISK_PATH" "mkpart lvm ext2 1G -1"
    parted -s "$DISK_PATH" "name 1 esp"
    parted -s "$DISK_PATH" "name 2 lvm"
    parted -s "$DISK_PATH" "toggle 1 boot"
    parted -s "$DISK_PATH" "toggle 2 lvm"
} # }}}
format_partitions() # {{{
{
    echo "Formatting partitions"
    get_partitions "$DISK"
    get_partition 0
    mkfs.vfat -F32 /dev/"$PART_NAME"
} # }}}
setup_luks() # {{{
{
    echo "Setting up encrypted partitions"
    get_partition 1
    echo -n "$ENCRPYTION_PASS" | cryptsetup luksFormat /dev/"$PART_NAME" -
    echo -n "$ENCRPYTION_PASS" | cryptsetup open --type luks /dev/"$PART_NAME" lvm -
    pvcreate /dev/mapper/lvm
    vgcreate volgroup /dev/mapper/lvm
    lvcreate -L 20G volgroup -n lvolswap
    lvcreate -l 100%FREE volgroup -n lvolroot
    mkswap -L swap /dev/mapper/volgroup-lvolswap
    mkfs.xfs -L root /dev/mapper/volgroup-lvolroot
} # }}}
mount_partitions() # {{{
{
    echo "Mounting partitions"
    mount /dev/mapper/volgroup-lvolroot /mnt
    swapon /dev/mapper/volgroup-lvolswap

    get_partition 0
    mkdir /mnt/efi
    mount "/dev/$PART_NAME" /mnt/efi
    mkdir -p /mnt/boot
    mkdir -p /mnt/efi/EFI/arch
    mount --bind /mnt/efi/EFI/arch /mnt/boot
} # }}}
function find_fastest_mirror() # {{{
{
  pacman -S --noconfirm reflector pacman-contrib
  #curl -s "https://www.archlinux.org/mirrorlist/?country=FR&country=GB&protocol=https&use_mirror_status=on" | sed -e 's/^#Server/Server/' -e '/^#/d' | rankmirrors -n 5 - > /etc/pacman.d/mirrorlist
  reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
  mkdir -p /mnt/etc/pacman.d
  cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
} # }}}
install_base_system() # {{{
{
    echo "Installing system"
    mkdir -p /mnt/etc/
    genfstab -L /mnt > /mnt/etc/fstab
    sed -i 's#/mnt/efi/EFI/arch#/efi/EFI/arch#' /mnt/etc/fstab
    pacstrap /mnt base base-devel curl efibootmgr btrfs-progs git ansible wget ruby-shadow linux linux-headers linux-zen linux-zen-headers linux-headers nvidia-dkms virtualbox-host-dkms iwd intel-ucode lvm2 xfsprogs linux-firmware
} # }}}
setup_locales() # {{{
{
    echo "Setting locale"
    chroot_command "sed -i 's/#en_GB/en_GB/g' /etc/locale.gen"
    chroot_command "sed -i 's/#en_US/en_US/g' /etc/locale.gen"
    chroot_command "locale-gen"
    echo 'LANG=en_GB.UTF-8' > /mnt/etc/locale.conf
} # }}}
setup_hostname() { # {{{
    echo "Setting hostname to $REQUIRED_HOSTNAME"
    #chroot_command "bash echo 'test' > /etc/hostname"
    echo "$REQUIRED_HOSTNAME" > /mnt/etc/hostname
    chroot_command "hostnamectl set-hostname \"$REQUIRED_HOSTNAME\""
} # }}}
create_initcpio() # {{{
{
    echo "Creating initcpio"
    chroot_command "sed -i 's/base udev autodetect modconf block filesystems keyboard fsck/base udev encrypt autodetect modconf block lvm2 resume filesystems keyboard fsck/g' /etc/mkinitcpio.conf"
    chroot_command "mkinitcpio -p linux"
    chroot_command "mkinitcpio -p linux-zen"
} # }}}
setup_systemd_boot() # {{{
{
    echo "Setting up systemd-boot"
    get_partition 1
    local LUKSUUID=$(blkid /dev/$PART_NAME | awk '{ print $2; }' | sed 's/"//g')

    chroot_command "bootctl --path=/efi/ install"

    echo "label Arch Linux" >> /mnt/efi/loader/entries/arch.conf
    echo "linux /EFI/arch/vmlinuz-linux" >> /mnt/efi/loader/entries/arch.conf
    echo "initrd /EFI/arch/intel-ucode.img" >> /mnt/efi/loader/entries/arch.conf
    echo "initrd /EFI/arch/initramfs-linux.img" >> /mnt/efi/loader/entries/arch.conf
    echo "options cryptdevice=${LUKSUUID}:lvm root=/dev/mapper/volgroup-lvolroot resume=/dev/mapper/volgroup-lvolswap rw initrd=/EFI/arch/initramfs-linux.img button.lid_init_state=open quiet splash loglevel=3 rd.udev.log-priority=3 vt.global_cursor_default=0 vga=current i915.fastboot=1 i915.enable_gvt=1 kvm.ignore_msrs=1 intel_iommu=on iommu=pt" >> /mnt/efi/loader/entries/arch.conf

    echo "label Arch Linux Zen" >> /mnt/efi/loader/entries/arch-zen.conf
    echo "initrd /EFI/arch/intel-ucode.img" >> /mnt/efi/loader/entries/arch-zen.conf
    echo "linux /EFI/arch/vmlinuz-linux-zen" >> /mnt/efi/loader/entries/arch-zen.conf
    echo "initrd /EFI/arch/initramfs-linux-zen.img" >> /mnt/efi/loader/entries/arch-zen.conf
    echo "options cryptdevice=${LUKSUUID}:lvm root=/dev/mapper/volgroup-lvolroot resume=/dev/mapper/volgroup-lvolswap rw initrd=/EFI/arch/initramfs-linux-zen.img button.lid_init_state=open quiet splash loglevel=3 rd.udev.log-priority=3 vt.global_cursor_default=0 vga=current i915.fastboot=1 i915.enable_gvt=1 kvm.ignore_msrs=1 intel_iommu=on iommu=pt" >> /mnt/efi/loader/entries/arch-zen.conf
} # }}}
get_ansible_code() # {{{
{
    chroot_command "rm -Rf /etc/ansible"
    chroot_command "git clone --depth=1 --recurse-submodules -j8 git@github.com:alanjjenkins/ansible.git /etc/ansible/"
} #}}}
run_ansible() # {{{
{
    cat <<'END' | arch-chroot /mnt su -l root
    cd /etc/ansible/
    ansible-playbook playbooks/desktop.yml
END
} # }}}

install_deps
select_install_disk
get_encryption_password
get_required_hostname
wipe_disk
partition_disk
format_partitions
setup_luks
mount_partitions
find_fastest_mirror
install_base_system
setup_locales
setup_hostname
create_initcpio
setup_systemd_boot
get_ansible_code
run_ansible
