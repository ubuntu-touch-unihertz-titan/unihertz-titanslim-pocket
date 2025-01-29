# Ubuntu Touch device tree for Unihertz Titan Pocket and Titan Slim

This is based on Halium 11.0, and uses the mechanism described in [this
page](https://github.com/ubports/porting-notes/wiki/GitLab-CI-builds-for-devices-based-on-halium_arm64-(Halium-9)).

**Unihertz are GPL violators** and have been [ignoring kernel source code
requests](https://www.reddit.com/r/UnihertzTitan/comments/i6m311/unihertz_are_gpl_violators_no_kernel_source_code/)
[sent](https://twitter.com/mariogrip/status/1346851913074171904) by multiple
people. Coincidentally, this heavily limits the possibilities for
alternative OS projects for this device. Current Ubuntu Touch adaptation in
this repo is based on prebuilt stock Android 11 kernel, and a bunch of workarounds/hacks to
get around kernel feature requirements for certain components, such as
partially missing namespaces support for Halium LXC container.

In particular, AppArmor LSM module [has been modified](https://github.com/ubuntu-touch-unihertz-titan/kernel-alps-mt6771/commits/halium-11.0-modules/security/apparmor)
to compile as loadable kernel module by resolving private kernel symbols
at initialization time. This allows to compile it in Linux kernel source tree
used as base for MT6771 chipset devices, and load it with stock kernel.
However, since LSMs are not designed to function as loadable modules, it
required quite a number of hacks and may crash the kernel if module is loaded
too late, so it's insmoded before running upstart init.

This project can be built manually (see the instructions below) or you can
download the ready-made artifacts from GitHub: take the [latest
archive](https://gitlab.com/ubports/community-ports/android10/unihertz-titan/unihertz-titan/-/jobs/artifacts/master/download?job=devel-flashable),
unpack the `artifacts.zip` file (make sure that all files are created inside a
directory called `out/`, then follow the instructions in the
[Install](#install) section.

## Status
* **Based on prebuilt stock kernel** (see above)
* Boots Ubuntu Touch OTA-24+ based on Ubuntu 16.04/xenial
* Ubuntu Touch based on Ubuntu 20.04/focal is currently in development by the UBPorts community (boots on the device, but has less available apps and some features may be broken)
* Expected to work (both 16.04 and 20.04):
  - Bluetooth
  - Camera (rear/front) for taking photos
  - Cellular connectivity/mobile data
  - Keyboard layout (select English - Unihertz Titan Pocket in Settings)
  - Sound
  - Wi-Fi
* Known issues:
  - Fingerprint sensor not functional
  - Video recording with cameras

Please make an Issue for other problems you find or things to be improved otherwise.

## How to build

To manually build this project, follow these steps:

```bash
ln -sf deviceinfo-TitanPocket deviceinfo # or deviceinfo-TitanSlim to build for Titan Slim
./build.sh -b workdir  # workdir is the name of the build directory
./build/prepare-fake-ota.sh out/device_Titan.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out
```

## Install

Update to latest stock Android 11 firmware and install a custom recovery like TWRP.

Download the [latest
artifacts archive](https://github.com/ubuntu-touch-unihertz-titan/unihertz-titanslim-pocket/actions/workflows/build.yml)
named images-$device-$release of the build job at GitHub Actions or build manually. After doing that, run

```bash
fastboot flash boot out/boot.img
fastboot reboot recovery
```

In TWRP, format the userdata partition to ext4 to remove encryption and ensure
it is mounted, then run from PC:

```bash
adb push out/ubuntu.img /data
adb reboot
```

Also, instead using TWRP can do next steps:

    1) mkdir userdata && mv ./TitanSlim-ubuntu.img userdata/ubuntu.img
    2) Run mke2fs -t ext4 -O \^metadata_csum userdata.img 5120000 -d userdata in upper-level folder
    3) fastboot flash boot out/boot.img (from github download)
    4) fastboot flash userdata userdata.img (from step 2)
    5) fastboot reboot
