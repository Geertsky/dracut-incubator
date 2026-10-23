# Dracut module for bare-metal-install using Ansible
This [dracut](https://dracut.wiki.kernel.org/index.php/Main_Page) module is created for the [ansible](https://docs.ansible.com/) bare-metal-install collection [tuxifier](https://github.com/Geertsky/tuxifier).

It features the following:
* It depends on the [dracut-sshd](https://github.com/gsauthof/dracut-sshd) module.
* It includes a `python` [conda](https://conda-forge.org/docs/) environment with support for [linux-system-roles.storage](https://github.com/linux-system-roles/storage) and some other basic tools in the initial ramdisk. By packaging a conda environment. (See: [python-nest](https://github.com/Geertsky/python-nest))
* It pauses the boot process just before the root filesystem gets mounted _(dracut `pre-mount` hook)_

This combination makes it possible to use [ansible](https://docs.ansible.com/) to:
* partition (a) disk(s)
* install an OS
* poweroff the machine<br>
or<br>
* continue the boot to the freshly installed OS and continue your ansible playbook from there.

## Installing the dracut-incubator module

* Clone this repository and copy or link the `dracut-incubator/94incubator` directory to the `/usr/lib/dracut/modules.d/` directory.

* Download the pre-packaged [python-nest.squashfs](https://verweggistan.eu/python-nest.squashfs) <br>
and place it in `/usr/lib/dracut/modules.d/94incubator/`

**Or** <br>

* build and modify the `python-nest.squashfs` as described here: [python-nest](https://github.com/Geertsky/python-nest) <br>
and place it in `/usr/lib/dracut/modules.d/94incubator/`
## Building the initramfs

The initramfs image can be built using the following command:

```
sudo dracut -NM -a "incubator network lvm mdraid crypt" incubator-initramfs-$(uname -r).img $(uname -r)
```

The extra dracut modules determine which storage layouts [linux-system-roles.storage](https://github.com/linux-system-roles/storage) can build in the initramfs:

| dracut module | adds | enables |
|---------------|------|---------|
| `lvm`         | `lvm2` tools and udev rules | LVM volume groups and logical volumes |
| `crypt`       | `cryptsetup` and its libraries | LUKS encrypted volumes |
| `mdraid`      | `mdadm`, the md udev rules (`63-md-raid-arrays.rules`, `64-md-raid-assembly.rules`) and the `raid*` and `dm-raid` kernel modules | md RAID (`type: raid`, or `raid_level` on an `lvm` pool) and LVM RAID volumes |

`mdraid` requires `mdadm` to be installed on the system the initramfs is built on. Without the md udev rules the storage role fails with `mdadm: /dev/vdX is busy - skipping`.

>[!NOTE]
>These modules only provide the tools in the initramfs used for the install. For the installed system the [tuxifier](https://github.com/Geertsky/tuxifier) role installs `cryptsetup` and `mdadm`, writes `/etc/crypttab` and `/etc/mdadm.conf` from the devices it created, and the kernel package builds the initramfs of the installed system, which selects the `crypt` and `mdraid` modules itself.

## Booting the incubator-initramfs
The initramfs file together with it's kernel need to be fed to the server by any way possible. For instance: PXE, virt-manager Direct kernel boot, customized grub.

### Required boot arguments

| kernel argument | description                                                                                                                                                                    |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|`rd.neednet=1`   |The initial ramdisk execution requires network accessibility.                                                                                                                    |
|`root=LABEL=root`|The `root` argument should be set to the device that contains the root filesystem after the install is finished.                                        |
|`enforcing=0`    |`selinux` should be disabled during the install.                                                                                                                               |

