#!/bin/bash
CURRENT_VERSION="v1.3.21-JackSparrow"

clear
set -euo pipefail

error_handler() {
    local exit_code=$?
    local failed_command="$BASH_COMMAND"
    local line_number="${BASH_LINENO[0]}"
    local script_file="${BASH_SOURCE[1]:-$0}"

    {
        echo "[!] Shiver me timbers! The script ran aground!"
        echo "[!] Exit code: $exit_code"
        echo "[!] Script: $script_file"
        echo "[!] Line: $line_number"
        echo "[!] Failed command: $failed_command"
    } 
    exit "$exit_code"
}

trap 'error_handler $LINENO' ERR

echo "surrealra1n - $CURRENT_VERSION"
echo "Tether Downgrader strictly for the iPhone 6 (iPhone7,2) to iOS 8.1, savvy?"
echo ""

# Request sudo password upfront
echo "Hand over the keys to the ship (Enter yer sudo password):"
sudo -v || exit 1

dist=0
DISTRO="Unsupported"
ARCH="$(uname -m)"

if [[ "$(uname)" == "Darwin" ]]; then
    DISTRO="macOS"
    dist=3
elif [[ -r /etc/os-release ]]; then
    . /etc/os-release
    if [[ "$ID" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
        DISTRO="Arch"
        dist=2
    elif [[ "$ID" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
        DISTRO="Debian"
        dist=1
    fi
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    zenity="./bin/zenity"
else
    zenity="zenity"
fi

stat_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

find_dmg() {
    dir="$1"
    mode="$2"
    max_size="${3:-}"

    find "$dir" -type f -name '*.dmg' ! -name '._*' -print |
    while IFS= read -r f; do
        size=$(stat_size "$f") || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf '%s %s\n' "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "[!] Blimey! Missing a vital piece of eight: $1"
        exit 1
    fi
}

echo "[*] Checkin' for the /bin/ chest..."
if [[ ! -d "bin" ]]; then
    echo "[!] Ye don't have the /bin/ folder! Walk the plank!"
    exit 1
fi

IDEVICE_INFO=$(ideviceinfo 2>&1) || true
IDEVICE_STATUS=$?

if [[ $IDEVICE_STATUS -eq 0 && "$IDEVICE_INFO" != *"No device found!"* ]]; then
    echo "[*] Vessel spotted in normal mode."
    IDENTIFIER=$(echo "$IDEVICE_INFO" | grep "^ProductType:" | cut -d ':' -f2 | xargs)
    ECID=$(echo "$IDEVICE_INFO" | grep "^UniqueChipID:" | cut -d ':' -f2 | xargs)
    SERIAL=$(echo "$IDEVICE_INFO" | grep "^SerialNumber:" | cut -d ':' -f2 | xargs)
    DEVICE_VERSION=$(echo "$IDEVICE_INFO" | grep "^ProductVersion:" | cut -d ':' -f2 | xargs)
else
    echo "[*] Vessel ain't in normal mode. Checking the depths (recovery/DFU)..."
    IRECOVERY_INFO=$(./bin/irecovery -q 2>/dev/null) || true
    if [[ -n "$IRECOVERY_INFO" ]]; then
        IDENTIFIER=$(echo "$IRECOVERY_INFO" | grep "^PRODUCT:" | cut -d ':' -f2 | xargs)
        ECID=$(echo "$IRECOVERY_INFO" | grep "^ECID:" | cut -d ':' -f2 | xargs)
    else
        echo "[!] No vessel detected. Check yer cables!"
        exit 1
    fi
fi

echo "[+] Device Identifier: $IDENTIFIER"
echo "[+] ECID: $ECID"

if [[ "$IDENTIFIER" != "iPhone7,2" ]]; then
    echo "[!] Avast! This script be forged ONLY for the iPhone 6 (iPhone7,2). Ye brought me a $IDENTIFIER!"
    exit 1
fi

LATEST_VERSION="12.5.8"
IBSS="iBSS.n61.RELEASE.im4p"
IBEC="iBEC.n61.RELEASE.im4p"
DEVICETREE="DeviceTree.n61ap.im4p"
ALLFLASH="all_flash.n61ap.production"
IBSS10="iBSS.n61.RELEASE.im4p"
IBEC10="iBEC.n61.RELEASE.im4p"
IBSS7="iBSS.n61ap.RELEASE.im4p"
IBEC7="iBEC.n61ap.RELEASE.im4p"
KERNELCACHE10="kernelcache.release.n61"
LLB="LLB.n61.RELEASE.im4p"
IBOOT="iBoot.n61.RELEASE.im4p"
USE_BASEBAND="--latest-baseband"

function usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --ipsw [TARGET_IPSW] [BASE_IPSW] [iOS_VERSION] [--stitch-activation]
        Create a custom IPSW for tethered restore with seprmvr64.
        Example: ./downgrade.sh --ipsw 8.1.ipsw 12.5.8.ipsw 8.1 --stitch-activation

  --restore [iOS_VERSION]
        Restore the device to a previously created custom IPSW.

  --boot [iOS_VERSION]
        Perform a tethered boot.

  --fix-ios8
        Fixes dyld over SSH ramdisk so iOS 8 won't get stuck at Slide to Upgrade. Run this after restoring!
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

case "$1" in
    --ipsw)
        TARGET_IPSW="$2"
        BASE_IPSW="$3"
        IOS_VERSION="$4"
        FORCE_ACTIVATE=1 # Hardcoded for 8.x

        if [[ "$IOS_VERSION" != "8.1" ]]; then
            echo "[!] This map leads to 8.1 only, savvy? But if ye insist on $IOS_VERSION, we shall proceed..."
        fi

        echo "[!] Activation records are REQUIRED for this voyage."
        echo "[!] Make sure yer vessel is on the latest iOS, fully activated, jailbroken, and has OpenSSH installed."
        
        # Normalize ECID
        if [[ "$ECID" == 0x* || "$ECID" == 0X* ]]; then
            ECID_CLEAN="${ECID#0x}"
            ECID_CLEAN="${ECID_CLEAN#0X}"
            ECID_DEC=$(printf '%d' "0x$ECID_CLEAN")
        else
            ECID_DEC="$ECID"
        fi
        CACHE_FILE="cache/$ECID_DEC"
        CACHED_SERIAL=$SERIAL

        if [[ ! -f "activation_records/$CACHED_SERIAL/activation_record.plist" ]]; then
            echo "[!] Let's plunder yer activation records over SSH!"
            mkdir -p activation_records/$CACHED_SERIAL/
            read -p "Insert the IP of yer device: " ip_address
            read -p "Enter the SSH Password (usually 'alpine'): " sshpwd
            CONNECT_AS="root"

            sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/containers/Data/System/*/Library/activation_records/activation_record.plist activation_records/$CACHED_SERIAL/activation_record.plist
            sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv activation_records/$CACHED_SERIAL/IC-Info.sisv
            sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist activation_records/$CACHED_SERIAL/com.apple.commcenter.device_specific_nobackup.plist
        fi

        echo "[*] Forging the custom IPSW..."
        savedir="noseprestore/$IDENTIFIER/$IOS_VERSION"
        mkdir -p "$savedir"
        unzip "$TARGET_IPSW" -d tmp1
        unzip "$BASE_IPSW" -d tmp2
        
        KEY_FILE="keys/$IDENTIFIER.txt"
        IBSS_KEY=$(grep "ibss-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
        IBEC_KEY=$(grep "ibec-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
        DTRE_KEY=$(grep "dtre-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
        RDSK_KEY=$(grep "rdsk-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
        KRNL_KEY=$(grep "krnl-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
        ROOT_KEY=$(grep "fstm-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)

        smallest_dmg=$(find_dmg tmp1 smallest)
        smallest12_dmg=$(find_dmg tmp2 smallest)
        rootfs_dmg=$(find_dmg tmp1 largest)
        rootfs12_dmg=$(find_dmg tmp2 largest)
        mkdir work
        rm -rf "$rootfs12_dmg"

        ./bin/img4 -i "$smallest_dmg" -o "$smallest12_dmg" -k $RDSK_KEY -D
        
        echo "[*] Patchin' ASR and the Restored External... hoist the colors!"
        ./bin/img4 -i "$smallest_dmg" -o "work/ramdisk.raw" -k $RDSK_KEY 
        ./bin/hfsplus "work/ramdisk.raw" grow 30000000
        ./bin/hfsplus "work/ramdisk.raw" extract usr/sbin/asr
        ./bin/asr64_patcher asr asr_patch 
        ./bin/ldid -e asr > ents.plist
        ./bin/ldid -Sents.plist asr_patch
        ./bin/hfsplus "work/ramdisk.raw" rm usr/sbin/asr
        ./bin/hfsplus "work/ramdisk.raw" add asr_patch usr/sbin/asr
        ./bin/hfsplus "work/ramdisk.raw" chmod 100755 usr/sbin/asr

        ./bin/hfsplus "work/ramdisk.raw" extract usr/local/bin/restored_external
        ./bin/restoredpatcher restored_external restored_patch -b
        ./bin/ldid -e restored_external > ents.plist
        ./bin/ldid -Sents.plist restored_patch
        ./bin/hfsplus "work/ramdisk.raw" rm usr/local/bin/restored_external
        ./bin/hfsplus "work/ramdisk.raw" add restored_patch usr/local/bin/restored_external
        ./bin/hfsplus "work/ramdisk.raw" chmod 100755 usr/local/bin/restored_external

        curl -L -o options.n61.plist https://github.com/pwnerblu/surrealra1n/raw/refs/heads/development/dualboot/options.n61.plist
        ./bin/hfsplus "work/ramdisk.raw" rm usr/local/share/restore/options.n61.plist
        ./bin/hfsplus "work/ramdisk.raw" add options.n61.plist usr/local/share/restore/options.n61.plist

        ./bin/img4 -i "work/ramdisk.raw" -o "$smallest12_dmg" -A -T rdsk
        ./bin/dmg extract "$rootfs_dmg" "tmp1/rootfs.raw" -k $ROOT_KEY
        ./bin/hfsplus "tmp1/rootfs.raw" grow 3500000000
        
        echo "Stitching activation files into the rootfs..."
        sudo cp activation_records/$CACHED_SERIAL/activation_record.plist activation.plist
        sudo cp activation_records/$CACHED_SERIAL/IC-Info.sisv IC-Info.sisv
        sudo cp activation_records/$CACHED_SERIAL/com.apple.commcenter.device_specific_nobackup.plist com.apple.commcenter.device_specific_nobackup.plist
        
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/root/Library/Lockdown/activation_records
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/mobile/Library/mad/activation_records
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/mobile/Library/FairPlay/iTunes_Control/iTunes
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless/Library
        ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless/Library/Preferences

        ./bin/hfsplus "tmp1/rootfs.raw" add activation.plist private/var/root/Library/Lockdown/activation_records/activation_record.plist
        ./bin/hfsplus "tmp1/rootfs.raw" add activation.plist private/var/mobile/Library/mad/activation_records/activation_record.plist
        ./bin/hfsplus "tmp1/rootfs.raw" add IC-Info.sisv private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv
        sudo ./bin/hfsplus "tmp1/rootfs.raw" add com.apple.commcenter.device_specific_nobackup.plist private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist
        
        ./bin/hfsplus "tmp1/rootfs.raw" chmod 666 private/var/root/Library/Lockdown/activation_records/activation_record.plist
        ./bin/hfsplus "tmp1/rootfs.raw" chmod 666 private/var/mobile/Library/mad/activation_records/activation_record.plist
        ./bin/hfsplus "tmp1/rootfs.raw" chmod 664 private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv
        ./bin/hfsplus "tmp1/rootfs.raw" chmod 600 private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist
        
        sudo rm -rf activation.plist IC-Info.sisv com.apple.commcenter.device_specific_nobackup.plist
        ./bin/dmg build "tmp1/rootfs.raw" "$rootfs12_dmg"

        ./bin/img4 -i "tmp1/Firmware/all_flash/$ALLFLASH/$DEVICETREE" -o "work/dtre.raw" -k $DTRE_KEY
        perl -pi -e 's/content-protect/content-protecV/g' work/dtre.raw 
        ./bin/img4 -i "work/dtre.raw" -o "tmp2/Firmware/all_flash/$DEVICETREE" -A -T rdtr
        
        mv "tmp1/Firmware/dfu/$IBSS10" "tmp1/Firmware/dfu/$IBSS7"
        mv "tmp1/Firmware/dfu/$IBEC10" "tmp1/Firmware/dfu/$IBEC7"
        ./bin/img4 -i "tmp1/Firmware/dfu/$IBSS7" -o "work/iBSS.dec" -k "$IBSS_KEY"
        ./bin/img4 -i "tmp1/Firmware/dfu/$IBEC7" -o "work/iBEC.dec" -k "$IBEC_KEY"
        
        ./bin/ipatcher work/iBSS.dec work/iBSS.patched
        ./bin/ipatcher work/iBEC.dec work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1"
        
        ./bin/img4 -i "work/iBSS.patched" -o "tmp2/Firmware/dfu/$IBSS" -A -T ibss   
        ./bin/img4 -i "work/iBEC.patched" -o "tmp2/Firmware/dfu/$IBEC" -A -T ibec 
        ./bin/img4 -i "tmp1/$KERNELCACHE10" -o "work/kcache.raw" -k $KRNL_KEY  
        ./bin/img4 -i "tmp1/$KERNELCACHE10" -o "work/kcache.im4p" -k $KRNL_KEY -D
        
        ./bin/Kernel64Patcher2 "work/kcache.raw" "work/kcache.patched" -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
        ./bin/kerneldiff "work/kcache.raw" "work/kcache.patched" "work/kcache.bpatch"
        ./bin/img4 -i "work/kcache.im4p" -o "tmp2/$KERNELCACHE" -T rkrn -P "work/kcache.bpatch" -J || true
        
        echo "[*] Packaging the plunder..."
        rm -rf "work" "tmp1"
        cd tmp2
        zip -0 -r ../$savedir/custom.ipsw *
        cd ..
        rm -rf "tmp2"
        echo "[*] IPSW forged! Run: ./downgrade.sh --restore $IOS_VERSION"
        exit 0
        ;;

    --restore)
        IOS_VERSION="$2"
        savedir="noseprestore/$IDENTIFIER/$IOS_VERSION"
        rm -rf "shsh"
        mkdir -p shsh
        sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh

        shshpath=$(find shsh -type f -name "*.shsh2" | head -n 1)
        
        echo "[*] Put yer vessel in PWNDFU mode. Pwning with gaster..."
        ./bin/gaster pwn
        ./bin/gaster reset
        
        irecovery_output=$(./bin/irecovery -q)
        if echo "$irecovery_output" | grep -q "PWND"; then
            echo "[*] PWNDFU verified!"
        else
            echo "[!] Not in PWNDFU. Do it properly, matey!"
            exit 1
        fi
        
        sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -e $savedir/custom.ipsw -y
        echo "[*] Restore complete! NOW YE MUST RUN: ./downgrade.sh --fix-ios8"
        exit 0
        ;;

    --fix-ios8)
        echo "[!] Ye must boot an SSH ramdisk with Legacy iOS Kit first to fix dyld."
        read -p "Press enter when the ramdisk is booted and ready..."
        echo "[*] Patching dyld. This might take a few turns of the hourglass..."
        ./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p6414 -o StrictHostKeyChecking=no "/sbin/mount_hfs /dev/disk0s1s1 /mnt1 || true"
        ./bin/sshpass -p "alpine" scp -P6414 -o StrictHostKeyChecking=no root@localhost:/mnt1/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64 dyld.raw
        ./bin/dsc64patcher dyld.raw dyld.patched -8
        ./bin/sshpass -p "alpine" scp -P6414 -o StrictHostKeyChecking=no dyld.patched root@localhost:/mnt1/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
        rm -rf dyld.patched dyld.raw
        ./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p6414 -o StrictHostKeyChecking=no "/sbin/reboot || true"
        echo "[*] Dyld fixed! Ye can now tether boot."
        exit 0
        ;;

    --boot)
        IOS_VERSION="$2"
        savedir="seprmvr64boot/$IDENTIFIER/$IOS_VERSION"
        shshpath=$(find shsh -type f -name "*.shsh2" | head -n 1)
        
        if [[ ! -d "$savedir" ]] || [[ ! -f "$savedir"/iBSS.img4 || ! -f "$savedir"/iBEC.img4 || ! -f "$savedir"/DeviceTree.img4 || ! -f "$savedir"/Kernelcache.img4 ]]; then
            echo "[*] Fetching boot files from the IPSW..."
            IPSW_PATH=$($zenity --file-selection --title="Select the iOS $IOS_VERSION IPSW file")
            rm -rf "$savedir"
            mkdir -p "$savedir" work tmp1
            unzip "$IPSW_PATH" -d tmp1
            
            KEY_FILE="keys/$IDENTIFIER.txt"
            ./bin/img4tool -s "$shshpath" -e -m "$IDENTIFIER-im4m"
            im4m="$IDENTIFIER-im4m"

            IBSS_KEY=$(grep "ibss-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
            IBEC_KEY=$(grep "ibec-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
            DTRE_KEY=$(grep "dtre-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
            KRNL_KEY=$(grep "krnl-$IOS_VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)

            ./bin/img4 -i "tmp1/Firmware/all_flash/$ALLFLASH/$DEVICETREE" -o "work/dtre.raw" -k $DTRE_KEY
            ./bin/img4 -i "work/dtre.raw" -o "$savedir/DeviceTree.img4" -A -T rdtr -M $im4m
            
            mv "tmp1/Firmware/dfu/$IBSS10" "tmp1/Firmware/dfu/$IBSS7"
            mv "tmp1/Firmware/dfu/$IBEC10" "tmp1/Firmware/dfu/$IBEC7"
            
            ./bin/img4 -i "tmp1/Firmware/dfu/$IBSS7" -o "work/iBSS.dec" -k $IBSS_KEY
            ./bin/img4 -i "tmp1/Firmware/dfu/$IBEC7" -o "work/iBEC.dec" -k $IBEC_KEY
            
            ./bin/ipatcher work/iBSS.dec work/iBSS.patched
            ./bin/ipatcher work/iBEC.dec work/iBEC.patched -b "-v rd=disk0s1s1"
            
            ./bin/img4 -i "work/iBSS.patched" -o "$savedir/iBSS.img4" -A -T ibss -M $im4m 
            ./bin/img4 -i "work/iBEC.patched" -o "$savedir/iBEC.img4" -A -T ibec -M $im4m
            
            ./bin/img4 -i "tmp1/$KERNELCACHE10" -o "work/kcache.raw" -k $KRNL_KEY  
            ./bin/img4 -i "tmp1/$KERNELCACHE10" -o "work/kcache.im4p" -k $KRNL_KEY -D
            
            ./bin/Kernel64Patcher2 "work/kcache.raw" "work/kcache.patched" -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
            ./bin/kerneldiff "work/kcache.raw" "work/kcache.patched" "work/kcache.bpatch"
            ./bin/img4 -i "work/kcache.im4p" -o "$savedir/Kernelcache.img4" -T rkrn -P "work/kcache.bpatch" -J -M $im4m || true
            
            rm -rf "work" "tmp1"
        fi

        echo "[*] Put yer vessel in PWNDFU mode..."
        ./bin/gaster pwn
        ./bin/gaster reset
        
        irecovery_output=$(./bin/irecovery -q)
        if ! echo "$irecovery_output" | grep -q "PWND"; then
            echo "[!] Not in PWNDFU! Overboard with ye!"
            exit 1
        fi
        
        ./bin/irecovery -f $savedir/iBSS.img4
        ./bin/irecovery -f $savedir/iBEC.img4
        ./bin/irecovery -f $savedir/DeviceTree.img4
        ./bin/irecovery -c devicetree
        ./bin/irecovery -f $savedir/Kernelcache.img4
        ./bin/irecovery -c bootx
        echo "[*] She's set sail! Yer device should boot now."
        exit 0
        ;;

    *)
        echo "[!] Unknown command. Consult the map!"
        usage
        exit 1
        ;;
esac	