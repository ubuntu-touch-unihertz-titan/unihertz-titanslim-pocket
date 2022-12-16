#!/bin/bash
set -xe
shopt -s extglob

[ -d build ] || git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools -b halium-11 build

BUILD_DIR=
OUT=

while [ $# -gt 0 ]
do
    case "$1" in
    (-b) BUILD_DIR="$(realpath "$2")"; shift;;
    (-o) OUT="$2"; shift;;
    (-*) echo "$0: Error: unknown option $1" 1>&2; exit 1;;
    (*) OUT="$2"; break;;
    esac
    shift
done

OUT="$(realpath "$OUT" 2>/dev/null || echo 'out')"
mkdir -p "$OUT"

if [ -z "$BUILD_DIR" ]; then
    TMP=$(mktemp -d)
    TMPDOWN=$(mktemp -d)
else
    TMP="$BUILD_DIR/tmp"
    # Clean up installation dir in case of local builds
    rm -rf "$TMP"
    mkdir -p "$TMP"
    TMPDOWN="$BUILD_DIR/downloads"
    mkdir -p "$TMPDOWN"
fi

HERE=$(pwd)
SCRIPT="$(dirname "$(realpath "$0")")"/build
if [ ! -d "$SCRIPT" ]; then
    SCRIPT="$(dirname "$SCRIPT")"
fi

mkdir -p "${TMP}/system" "${TMP}/partitions"

source "${HERE}/deviceinfo"

case $deviceinfo_arch in
    "armhf") RAMDISK_ARCH="armhf";;
    "aarch64") RAMDISK_ARCH="arm64";;
    "x86") RAMDISK_ARCH="i386";;
esac

cd "$TMPDOWN"
    [ -d aarch64-linux-android-4.9 ] || git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 -b pie-gsi --depth 1
    GCC_PATH="$TMPDOWN/aarch64-linux-android-4.9"
    if $deviceinfo_kernel_clang_compile; then
        [ -d linux-x86 ] || git clone https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 -b android11-gsi --depth 1
        CLANG_PATH="$TMPDOWN/linux-x86/clang-r383902"
        rm -rf "$TMPDOWN/linux-x86/.git" "$TMPDOWN/linux-x86/"!(clang-r383902)
    fi
    if [ "$deviceinfo_arch" == "aarch64" ]; then
        [ -d arm-linux-androideabi-4.9 ] || git clone https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 -b pie-gsi --depth 1
        GCC_ARM32_PATH="$TMPDOWN/arm-linux-androideabi-4.9"
    fi
    KERNEL_DIR="$(basename "${deviceinfo_kernel_source}")"
    KERNEL_DIR="${KERNEL_DIR%.*}"
    [ -d "$KERNEL_DIR" ] || git clone "$deviceinfo_kernel_source" -b $deviceinfo_kernel_source_branch --depth 1 --recursive

    [ -f halium-boot-ramdisk.img ] || curl --location --output halium-boot-ramdisk.img \
        "https://github.com/Halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-${RAMDISK_ARCH}"

    if ([ -n "$deviceinfo_kernel_apply_overlay" ] && $deviceinfo_kernel_apply_overlay) || [ -n "$deviceinfo_dtbo" ]; then
        [ -d libufdt ] || git clone https://android.googlesource.com/platform/system/libufdt -b pie-gsi --depth 1
        [ -d dtc ] || git clone https://android.googlesource.com/platform/external/dtc -b pie-gsi --depth 1
    fi

    [ -d "avb" ] || git clone https://android.googlesource.com/platform/external/avb -b android13-gsi --depth 1

    if [ -n "$deviceinfo_kernel_use_dtc_ext" ] && $deviceinfo_kernel_use_dtc_ext; then
        [ -f "dtc_ext" ] || curl --location https://android.googlesource.com/platform/prebuilts/misc/+/refs/heads/android10-gsi/linux-x86/dtc/dtc?format=TEXT | base64 --decode > dtc_ext
        chmod +x dtc_ext
    fi

    if [ ! -f "vbmeta.img" ] && [ -n "$deviceinfo_bootimg_append_vbmeta" ] && $deviceinfo_bootimg_append_vbmeta; then
        wget https://dl.google.com/developers/android/qt/images/gsi/vbmeta.img
    fi

    ls .
cd "$HERE"

if [ -n "$deviceinfo_kernel_apply_overlay" ] && $deviceinfo_kernel_apply_overlay; then
    "$SCRIPT/build-ufdt-apply-overlay.sh" "${TMPDOWN}"
fi

if [ -n "$deviceinfo_kernel_use_dtc_ext" ] && $deviceinfo_kernel_use_dtc_ext; then
    export DTC_EXT="$TMPDOWN/dtc_ext"
fi

if [ -n "$deviceinfo_kernel_force_scmversion" ]; then
    echo "$deviceinfo_kernel_force_scmversion" > "${TMPDOWN}/${KERNEL_DIR}/.scmversion"
fi

if $deviceinfo_kernel_clang_compile; then
    if [ -n "$deviceinfo_kernel_use_lld" ] && $deviceinfo_kernel_use_lld; then
        export LD=ld.ldd
    fi
    CC=clang \
    CLANG_TRIPLE=${deviceinfo_arch}-linux-gnu- \
    PATH="$CLANG_PATH/bin:$GCC_PATH/bin:$GCC_ARM32_PATH/bin:${PATH}" \
    "$SCRIPT/build-kernel.sh" "${TMPDOWN}" "${TMP}/system"
else
    PATH="$GCC_PATH/bin:$GCC_ARM32_PATH/bin:${PATH}" \
    "$SCRIPT/build-kernel.sh" "${TMPDOWN}" "${TMP}/system"
fi

if [ -n "$deviceinfo_bootimg_prebuilt_kernel" ]; then
    case "$deviceinfo_arch" in
        aarch64*) ARCH="arm64" ;;
        arm*) ARCH="arm" ;;
        x86_64) ARCH="x86_64" ;;
        x86) ARCH="x86" ;;
    esac
    mkdir -p "${TMPDOWN}/KERNEL_OBJ/arch/$ARCH/boot"
    gzip -c "$deviceinfo_bootimg_prebuilt_kernel" > "${TMPDOWN}/KERNEL_OBJ/arch/$ARCH/boot/Image.gz"
fi

if [ -n "$deviceinfo_prebuilt_dtbo" ]; then
    cp "$deviceinfo_prebuilt_dtbo" "${TMP}/partitions/dtbo.img"
elif [ -n "$deviceinfo_dtbo" ]; then
    "$SCRIPT/make-dtboimage.sh" "${TMPDOWN}" "${TMPDOWN}/KERNEL_OBJ" "${TMP}/partitions/dtbo.img"
fi

"$SCRIPT/make-bootimage.sh" "${TMPDOWN}" "${TMPDOWN}/KERNEL_OBJ" "${TMPDOWN}/halium-boot-ramdisk.img" "${TMP}/partitions/boot.img"

cp -av overlay/* "${TMP}/"
if [ -d overlay-${deviceinfo_codename} ]; then
    cp -av overlay-${deviceinfo_codename}/* "${TMP}/"
fi

INITRC_PATHS="
${TMP}/system/opt/halium-overlay/system/etc/init
${TMP}/system/usr/share/halium-overlay/system/etc/init
${TMP}/system/opt/halium-overlay/vendor/etc/init
${TMP}/system/usr/share/halium-overlay/vendor/etc/init
"
while IFS= read -r path ; do
    if [ -d "$path" ]; then
        find "$path" -type f -exec chmod 644 {} \;
    fi
done <<< "$INITRC_PATHS"

BUILDPROP_PATHS="
${TMP}/system/opt/halium-overlay/system
${TMP}/system/usr/share/halium-overlay/system
${TMP}/system/opt/halium-overlay/vendor
${TMP}/system/usr/share/halium-overlay/vendor
"
while IFS= read -r path ; do
    if [ -d "$path" ]; then
        find "$path" -type f -name "build.prop" -exec chmod 600 {} \;
    fi
done <<< "$BUILDPROP_PATHS"

if [ -z "$deviceinfo_use_overlaystore" ]; then
    "$SCRIPT/build-tarball-mainline.sh" "${deviceinfo_codename}" "${OUT}" "${TMP}"

    # Copy focal-specific overlay
    cp -av overlay-focal/* "${TMP}/"
    # create device tarball for https://wiki.debian.org/UsrMerge rootfs
    "$SCRIPT/build-tarball-mainline.sh" "${deviceinfo_codename}" "${OUT}" "${TMP}" "usrmerge"
else
    "$SCRIPT/build-tarball-mainline.sh" "${deviceinfo_codename}" "${OUT}" "${TMP}" "overlaystore"
    # create a symlink for _usrmerge variant so that common pipeline just works.
    ln -sf "device_${deviceinfo_codename}.tar.xz" "${OUT}/device_${deviceinfo_codename}_usrmerge.tar.xz"
fi

if [ -z "$BUILD_DIR" ]; then
    rm -r "${TMP}"
    rm -r "${TMPDOWN}"
fi

echo "done"
