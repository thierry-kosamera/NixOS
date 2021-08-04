 --packages git --run "git -C ${config_dir} \
                                        commit \
        --message 'Commit encryption key for ${TARGET_HOSTNAME}.'"
        nix-shell --packages git --run "git -C ${config_dir} \
        push -u origin ${branch_name}"
        
        echo -e "\n\nThe encryption key for this server was committed to GitHub"
        echo -e "Please go to the following link to create a pull request:"
        echo -e "\nhttps://github.com/thierry-kosamera/emn-org-config/pull/new/${branch_name}\n"
        echo -e "The installer will continue once the pull request has been merged into master."
        
        nix-shell --packages git --run "git -C ${config_dir} \
        checkout master"
        
        while [ ! -f "${keyfile}" ]; do
            nix-shell --packages git --run "git -C ${config_dir} \
            pull > /dev/null 2>&1"
            decrypt_secrets
            if [ ! -f "${keyfile}" ]; then
                sleep 10
            fi
        done
    fi
fi

detect_swap="$(swapon | grep "${swapfile}" > /dev/null 2>&1; echo $?)"
if [ "${detect_swap}" -eq "0" ]; then
    swapoff "${swapfile}"
    rm --force "${swapfile}"
fi

MP=$(mountpoint --quiet /mnt/; echo $?) || true
if [ "${MP}" -eq "0" ]; then
    umount -R /mnt/
fi

cryptsetup close nixos_data_decrypted || true
vgremove --force LVMVolGroup || true
# If the existing partition table is GPT, we use the partlabel
pvremove /dev/disk/by-partlabel/nixos_lvm || true
# If the existing partition table is MBR, we need to use direct addressing
pvremove "${DEVICE}2" || true

if [ "${USE_UEFI}" = true ]; then
    # Using zeroes for the start and end sectors, selects the default values, i.e.:
    #   the next unallocated sector for the start value
    #   the last sector of the device for the end value
    sgdisk --clear --mbrtogpt "${DEVICE}"
    sgdisk --new=1:2048:+512M --change-name=1:"efi"        --typecode=1:ef00 "${DEVICE}"
    sgdisk --new=2:0:+512M    --change-name=2:"nixos_boot" --typecode=2:8300 "${DEVICE}"
    sgdisk --new=3:0:0        --change-name=3:"nixos_lvm"  --typecode=3:8e00 "${DEVICE}"
    sgdisk --print "${DEVICE}"
    
    wait_for_devices "/dev/disk/by-partlabel/efi" \
    "/dev/disk/by-partlabel/nixos_boot" \
    "/dev/disk/by-partlabel/nixos_lvm"
else
    sfdisk --wipe            always \
    --wipe-partitions always \
    "${DEVICE}" \
<<EOF
label: dos
unit:  sectors

# Boot partition
type=83, start=2048, size=512MiB, bootable

# LVM partition, from first unallocated sector to end of disk
# These start and size values are the defaults when nothing is specified
type=8e
EOF
fi

if [ "${USE_UEFI}" = true ]; then
    BOOT_PART="/dev/disk/by-partlabel/nixos_boot"
    LVM_PART="/dev/disk/by-partlabel/nixos_lvm"
else
    BOOT_PART="${DEVICE}1"
    LVM_PART="${DEVICE}2"
fi

wait_for_devices "${LVM_PART}"
pvcreate "${LVM_PART}"
wait_for_devices "${LVM_PART}"
vgcreate LVMVolGroup "${LVM_PART}"
lvcreate --yes --size "${ROOT_SIZE}"GB --name nixos_root LVMVolGroup
wait_for_devices "/dev/LVMVolGroup/nixos_root"

if [ "${USE_UEFI}" = true ]; then
    wipefs --all /dev/disk/by-partlabel/efi
    mkfs.vfat -n EFI -F32 /dev/disk/by-partlabel/efi
fi
wipefs --all "${BOOT_PART}"
mkfs.ext4 -e remount-ro -L nixos_boot "${BOOT_PART}"
mkfs.ext4 -e remount-ro -L nixos_root /dev/LVMVolGroup/nixos_root

if [ "${USE_UEFI}" = true ]; then
    wait_for_devices "/dev/disk/by-label/EFI"
fi
wait_for_devices "/dev/disk/by-label/nixos_boot" \
"/dev/disk/by-label/nixos_root"

mount /dev/disk/by-label/nixos_root /mnt
mkdir --parents /mnt/boot
mount /dev/disk/by-label/nixos_boot /mnt/boot
if [ "${USE_UEFI}" = true ]; then
    mkdir --parents /mnt/boot/efi
    mount /dev/disk/by-label/EFI /mnt/boot/efi
fi

fallocate -l 2G "${swapfile}"
chmod 0600 "${swapfile}"
mkswap "${swapfile}"
swapon "${swapfile}"

rm --recursive --force /mnt/etc/
nix-shell --packages git --run "git clone ${main_repo} \
/mnt/etc/nixos/"
nix-shell --packages git --run "git clone ${config_repo} \
/mnt/etc/nixos/org-config"
nixos-generate-config --root /mnt --no-filesystems
ln --symbolic org-config/hosts/"${TARGET_HOSTNAME}".nix /mnt/etc/nixos/settings.nix
cp /tmp/id_tunnel /tmp/id_tunnel.pub /mnt/etc/nixos/local/

if [ "${CREATE_DATA_PART}" = true ]; then
    # Do this only after having generated the hardware config
    lvcreate --yes --extents 100%FREE --name nixos_data LVMVolGroup
    wait_for_devices "/dev/LVMVolGroup/nixos_data"
    
    mkdir --parents /run/cryptsetup
    cryptsetup --verbose \
    --batch-mode \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --use-urandom \
    luksFormat \
    --type luks2 \
    --key-file "${secrets_dir}/keyfile" \
    /dev/LVMVolGroup/nixos_data
    cryptsetup open \
    --key-file "${secrets_dir}/keyfile" \
    /dev/LVMVolGroup/nixos_data nixos_data_decrypted
    mkfs.ext4 -e remount-ro \
    -m 1 \
    -L nixos_data \
    /dev/mapper/nixos_data_decrypted
    
    wait_for_devices "/dev/disk/by-label/nixos_data"
    
    mkdir --parents /mnt/opt
    mount /dev/disk/by-label/nixos_data /mnt/opt
    mkdir --parents /mnt/home
    mkdir --parents /mnt/opt/.home
    mount --bind /mnt/opt/.home /mnt/home
fi

# TODO: remove the next line when the following issue in nixpkgs has been resolved:
# https://github.com/NixOS/nixpkgs/issues/126141
nix-build '<nixpkgs/nixos>' -A config.system.build.toplevel -I nixos-config=/mnt/etc/nixos/configuration.nix
nixos-install --no-root-passwd --max-jobs 4

swapoff "${swapfile}"
rm -f "${swapfile}"

if [ "${CREATE_DATA_PART}" = true ]; then
    umount -R /mnt/home
    umount -R /mnt/opt
    cryptsetup close nixos_data_decrypted
fi

echo -e "\nNixOS installation finished, please reboot using \"sudo systemctl reboot\""

