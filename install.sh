#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "Not booted in UEFI mode."; exit 1; }

echo "Available disks:"
lsblk -dpno NAME,SIZE,MODEL | grep -v -E 'loop|sr[0-9]'
echo
read -rp "Disk to install to (e.g. /dev/sda): " DISK
[[ -b "$DISK" ]] || { echo "$DISK is not a block device."; exit 1; }

read -rp "Username: " USERNAME
read -rp "Hostname: " HOSTNAME_

echo
echo "Keyboard layout (console keymap). Examples: us, pl, es, de, fr, lt"
echo "Type 'list' to see all, or press Enter for us."
while true; do
    read -rp "Keymap [us]: " KEYMAP
    KEYMAP="${KEYMAP:-us}"
    if [[ "$KEYMAP" == "list" ]]; then
        localectl list-keymaps | less
        continue
    fi
    if localectl list-keymaps | grep -qx -- "$KEYMAP"; then
        loadkeys "$KEYMAP"
        break
    fi
    echo "Unknown keymap '$KEYMAP', try again."
done

while true; do
    read -rsp "Password (used for user and root): " PASS; echo
    read -rsp "Repeat password: " PASS2; echo
    [[ "$PASS" == "$PASS2" && -n "$PASS" ]] && break
    echo "Passwords empty or do not match, try again."
done

echo
echo "!!! ALL DATA ON $DISK WILL BE ERASED !!!"
read -rp "Type the disk path again to confirm: " CONFIRM
[[ "$CONFIRM" == "$DISK" ]] || { echo "Mismatch, aborting."; exit 1; }

if [[ "$DISK" =~ [0-9]$ ]]; then P="${DISK}p"; else P="$DISK"; fi
EFI="${P}1"; SWAP="${P}2"; ROOT="${P}3"

RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
SWAP_GB=$(( (RAM_KB + 1048575) / 1048576 ))

# 1. Partitioning
swapoff -a || true
umount -R /mnt 2>/dev/null || true
wipefs -af "$DISK"
sfdisk "$DISK" <<EOF
label: gpt
,1G,U
,${SWAP_GB}G,S
,,L
EOF
partprobe "$DISK"
sleep 2

# 2. Format, swap, subvolumes
mkfs.fat -F32 "$EFI"
mkswap "$SWAP"
swapon "$SWAP"
mkfs.btrfs -f -L "Linux" "$ROOT"

mount "$ROOT" /mnt
for sv in @ @home @log @cache @snapshots; do
    btrfs subvolume create "/mnt/$sv"
done
umount /mnt

# 3. Mount subvolumes
OPTS="noatime,compress=zstd,space_cache=v2"
mount -o "$OPTS,subvol=@" "$ROOT" /mnt
mkdir -p /mnt/{boot/efi,home,var/log,var/cache,.snapshots}
mount -o "$OPTS,subvol=@home" "$ROOT" /mnt/home
mount -o "$OPTS,subvol=@log" "$ROOT" /mnt/var/log
mount -o "$OPTS,subvol=@cache" "$ROOT" /mnt/var/cache
mount -o "$OPTS,subvol=@snapshots" "$ROOT" /mnt/.snapshots
mount "$EFI" /mnt/boot/efi

# 4. Base system
pacstrap -K /mnt base base-devel linux linux-headers linux-firmware btrfs-progs \
    vim nano networkmanager grub efibootmgr snapper snap-pac grub-btrfs git fish \
    terminus-font fastfetch

# 5. fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 6-12. Configuration inside chroot
cat > /mnt/root/chroot.sh <<'CHROOT'
set -euo pipefail

# 7. Timezone / locale / hostname
ln -sf /usr/share/zoneinfo/Europe/Vilnius /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
printf 'KEYMAP=%s\nFONT=ter-v16n\n' "$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME_" > /etc/hostname
cat >> /etc/hosts <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  $HOSTNAME_
EOF

# 8. Users & passwords
useradd -m -G wheel -s /bin/fish "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$PASS" | chpasswd
printf 'root:%s\n' "$PASS" | chpasswd
sed -i 's/^# *\(%wheel ALL=(ALL:ALL) ALL\)$/\1/' /etc/sudoers

# 9. Services
systemctl enable NetworkManager

# 10. Bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# 12. Snapper
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount /.snapshots
chmod 750 /.snapshots
chown ":$USERNAME" /.snapshots

CFG=/etc/snapper/configs/root
sed -i 's/^TIMELINE_MIN_AGE=.*/TIMELINE_MIN_AGE="3600"/' $CFG
sed -i 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="4"/' $CFG
sed -i 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="3"/' $CFG
sed -i 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="3"/' $CFG
sed -i 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="2"/' $CFG
sed -i 's/^TIMELINE_LIMIT_QUARTERLY=.*/TIMELINE_LIMIT_QUARTERLY="1"/' $CFG
sed -i 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' $CFG

systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

arch-chroot /mnt /usr/bin/env \
    USERNAME="$USERNAME" HOSTNAME_="$HOSTNAME_" PASS="$PASS" KEYMAP="$KEYMAP" \
    bash /root/chroot.sh

rm -f /mnt/root/chroot.sh

# 11. Finish
sync
umount -R /mnt
echo
echo "Done. Remove the install USB and run: reboot"
