# a simplified uefivars replacement
(( $USING_UEFI_BOOTLOADER )) || return

[[ ! -d $VAR_DIR/recovery ]] && mkdir -p -m 755 $VAR_DIR/recovery
rm -f $VAR_DIR/recovery/uefi-variables

EFIBOOTMGR_OUTPUT=$TMP_DIR/efibootmgr_output
efibootmgr > $EFIBOOTMGR_OUTPUT

# depending the directory ends on vars or efivars we need to treat it different
if [ "$SYSFS_DIR_EFI_VARS" = "/sys/firmware/efi/vars" ]; then

    for uefi_dir in $(ls $SYSFS_DIR_EFI_VARS)
    do
        uefi_var=$(echo $uefi_dir | cut -d- -f 1)
        [[ "$uefi_var" = "new_var" ]] && continue
        [[ "$uefi_var" = "del_var" ]] && continue
        efi_data="$(efibootmgr_read_var $uefi_var $EFIBOOTMGR_OUTPUT)"
        [[ -z "$efi_data" ]] && efi_data="$(uefi_read_data $SYSFS_DIR_EFI_VARS/$uefi_dir/data)"
        efi_attr="$(uefi_read_attributes $SYSFS_DIR_EFI_VARS/$uefi_dir/attributes)"
        echo "$uefi_var $efi_attr: $efi_data"  >> $VAR_DIR/recovery/uefi-variables
    done
    # finding the correct EFI bootloader in use (UEFI_BOOTLOADER=)
    BootCurrent=$(grep BootCurrent $VAR_DIR/recovery/uefi-variables | cut -d: -f2 | awk '{print $1}')	# 0000
    UEFI_BOOTLOADER=$(uefi_extract_bootloader $SYSFS_DIR_EFI_VARS/Boot${BootCurrent}-*/data)

elif [ "$SYSFS_DIR_EFI_VARS" = "/sys/firmware/efi/efivars" ]; then

    for uefi_file in $(ls $SYSFS_DIR_EFI_VARS)
    do
        uefi_var=$(echo $uefi_file | cut -d- -f 1)
        efi_data="$(efibootmgr_read_var $uefi_var $EFIBOOTMGR_OUTPUT)"
        [[ -z "$efi_data" ]] && efi_data="$(uefi_read_data $SYSFS_DIR_EFI_VARS/$uefi_file)"
        echo "$uefi_var $efi_attr: $efi_data"  >> $VAR_DIR/recovery/uefi-variables
        #TODO: efi_attr how to extract??
    done
    # finding the correct EFI bootloader in use (UEFI_BOOTLOADER=)
    BootCurrent=$(grep BootCurrent $VAR_DIR/recovery/uefi-variables | cut -d: -f2 | awk '{print $1}')	# 0000
    UEFI_BOOTLOADER=$(uefi_extract_bootloader $SYSFS_DIR_EFI_VARS/Boot${BootCurrent}-*)

else
    BugError "UEFI Variables directory $SYSFS_DIR_EFI_VARS is not what I expected"
fi

# the UEFI_BOOTLOADER contains path in DOS format
UEFI_BOOTLOADER="/boot/efi"$(echo "$UEFI_BOOTLOADER" | sed -e 's;\\;/;g')
if [[ ! -f ${UEFI_BOOTLOADER} ]]; then
    UEFI_BOOTLOADER=$(find /boot/efi -name "grub*.efi" | tail -1)
fi
[[ ! -f ${UEFI_BOOTLOADER} ]] && Error "Cannot find a proper UEFI_BOOTLOADER ($UEFI_BOOTLOADER). 
Please define one manual in /etc/rear/local.conf"
