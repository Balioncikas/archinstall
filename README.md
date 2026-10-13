# Arch Linux Install & Post-Install

An interactive Arch Linux installer script plus a step-by-step post-install guide. The result is a UEFI + Btrfs system with automatic snapshots, bootable from GRUB, followed by a Hyprland desktop with a greetd/tuigreet login screen.

## Files

| File | What it is |
|------|------------|
| `install.sh` | Interactive installer. Partitions the disk, sets up Btrfs, installs the base system, configures the bootloader and snapper. Run from the Arch live ISO. |
| `postinstall.txt` | Manual guide to follow after first boot: network, pacman, drivers, AUR helper, greetd, Hyprland, Bluetooth, tools, firewall, Btrfs maintenance. |

## Requirements

- Arch Linux live ISO booted in **UEFI mode**
- Working internet connection in the live environment
- A disk you are fine **wiping completely**
- AMD GPU (the post-install guide assumes AMD; NVIDIA notes are included in the GPU section)

## Part 1: `install.sh`

### Usage

From the live ISO, as root:

```
pacman -Sy git
git clone <this-repo-url>
cd <repo>
bash install.sh
```

### What it asks you

1. Target disk (e.g. `/dev/sda`, `/dev/nvme0n1`)
2. Username
3. Hostname
4. Console keymap (`us` by default, type `list` to browse)
5. Password (used for both the user and root)
6. Confirmation: you must retype the disk path

### What it does

**Partitioning (GPT)**

| Partition | Size | Use |
|-----------|------|-----|
| 1 | 1 GiB | EFI system partition (FAT32), mounted at `/boot/efi` |
| 2 | Equal to your RAM, rounded up | Swap |
| 3 | Remainder | Btrfs root |

**Btrfs subvolumes**

| Subvolume | Mount point |
|-----------|-------------|
| `@` | `/` |
| `@home` | `/home` |
| `@log` | `/var/log` |
| `@cache` | `/var/cache` |
| `@snapshots` | `/.snapshots` |

Mount options: `noatime,compress=zstd,space_cache=v2`.

**Base system** (via `pacstrap`)

`base base-devel linux linux-headers linux-firmware btrfs-progs vim nano networkmanager grub efibootmgr snapper snap-pac grub-btrfs git fish terminus-font fastfetch`

**System configuration**

- Timezone `Europe/Vilnius`, locale `en_US.UTF-8`
- Console font `ter-v16n`, keymap as chosen
- User created in the `wheel` group with `fish` as the shell, sudo enabled for `wheel`
- NetworkManager enabled
- GRUB installed to the EFI partition

**Snapshots**

- snapper configured for `/` with a modest timeline retention (4 hourly, 3 daily, 3 weekly, 2 monthly, 1 quarterly, no yearly)
- `snap-pac` takes pre/post snapshots around pacman transactions
- `grub-btrfsd` adds snapshots to the GRUB boot menu

When it finishes, remove the USB stick and run `reboot`.

### Things to change before running

The timezone (`Europe/Vilnius`) and locale are hardcoded in the script. Edit the chroot section of `install.sh` if you want something different.

> **Warning:** the selected disk is wiped without any way to recover it. Double-check the disk path.

## Part 2: `postinstall.txt`

This is a guide to work through by hand after first boot, logged in as your normal user (not root). Replace every `PLACEHOLDER` before running a command.

1. **Network & time**: connect with `nmtui`/`nmcli`, enable NTP
2. **Pacman setup**: enable multilib, refresh mirrors with reflector, enable `reflector`, `paccache` and `fstrim` timers
3. **CPU microcode**: `amd-ucode` (or `intel-ucode`), regenerate GRUB config
4. **GPU drivers (AMD)**: Mesa, Vulkan, 32-bit libs, Steam/gamemode/MangoHud
5. **AUR helper**: paru
6. **greetd + tuigreet**: login manager with session menu and remembered session
7. **Hyprland**: installed through `caelestia-cli`
8. **Bluetooth**: bluez and pairing with `bluetoothctl`
9. **Everyday tools**: shell, CLI utilities, filesystem support, Dolphin
10. **Firewall** (optional): ufw with deny-incoming defaults
11. **Btrfs maintenance**: monthly scrub, btrfs-assistant, snapper checks
12. **Reboot & verify**: confirm Wayland session and a clean `systemctl --failed`

## Recovering from a bad update

Because snapper and grub-btrfs are set up, you can boot an earlier snapshot from the **Arch Linux snapshots** submenu in GRUB, then roll back or inspect with `snapper -c root list` or `btrfs-assistant`.

## Troubleshooting

- **"Not booted in UEFI mode"**: reboot the ISO in UEFI mode. The script does not support legacy BIOS.
- **tuigreet shows a black screen**: switch to another TTY (`Ctrl+Alt+F2`), log in, and check `journalctl -u greetd -b`.
- **Wi-Fi not connected after first boot**: NetworkManager is enabled, but you still connect manually with `nmtui`.
