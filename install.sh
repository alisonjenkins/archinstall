#/bin/bash

function hostname()
{
    echo "What do you want to name the computer?"
    read hostname
    echo "$hostname" > /etc/hostname
}

function timezone()
{
    ln -s /usr/share/zoneinfo/Europe/London /etc/localtime
}

function enable_locales()
{
    LOCALES=( en_GB en_US )
    for locale in "${LOCALES[@]}"
    do
        sed -i '/^#$locale /s/^#//' /etc/locale.gen
    done

    locale-gen

    # main locale is the first argument to the locales array
    echo "LANG=$LOCALES[0].UTF-8" > /etc/locale.conf
}

function set_keymap()
{
    echo "KEYMAP=uk" > /etc/vconsole.conf
}

function mkinitcpio()
{
    mkinitcpio -p linux
}

function install_bootloader()
{
    bootctl install --path=/boot
}

function install_packages()
{
    pacman -Sy \
        vim


}
