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
    mkdir -p "$TMP"
    TMPDOWN="$BUILD_DIR/downloads"
    mkdir -p "$TMPDOWN"
fi

HERE=$(pwd)
SCRIPT="$(dirname "$(realpath "$0")")"/build
if [ ! -d "$SCRIPT" ]; then
    SCRIPT="$(dirname "$SCRIPT")"
fi

mkdir -p "${TMP}/system"
mkdir -p "${TMP}/partitions"

source "${HERE}/deviceinfo"

case $deviceinfo_arch in
    "armhf") RAMDISK_ARCH="armhf";;
    "aarch64") RAMDISK_ARCH="arm64";;
    "x86") RAMDISK_ARCH="i386";;
esac

cd "$TMPDOWN"
    [ -f halium-boot-ramdisk.img ] || curl --location --output halium-boot-ramdisk.img \
        "https://github.com/Halium/initramfs-tools-halium/releases/download/dynparts/initrd.img-touch-${RAMDISK_ARCH}"

    [ -d "avb" ] || git clone https://android.googlesource.com/platform/external/avb -b android10-gsi --depth 1

    if [ ! -f "vbmeta.img" ] && [ -n "$deviceinfo_bootimg_append_vbmeta" ] && $deviceinfo_bootimg_append_vbmeta; then
        wget https://dl.google.com/developers/android/qt/images/gsi/vbmeta.img
    fi

    ls .
cd "$HERE"

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
"$SCRIPT/build-tarball-mainline.sh" "${deviceinfo_codename}" "${OUT}" "${TMP}"

cp -av overlay-focal/* "${TMP}/"
# create device tarball for https://wiki.debian.org/UsrMerge rootfs
"$SCRIPT/build-tarball-mainline.sh" "${deviceinfo_codename}" "${OUT}" "${TMP}" "usrmerge"

if [ -z "$BUILD_DIR" ]; then
    rm -r "${TMP}"
    rm -r "${TMPDOWN}"
fi

echo "done"
