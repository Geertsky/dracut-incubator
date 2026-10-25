# Dracut module for bare-metal-install using Ansible
This [dracut](https://dracut.wiki.kernel.org/index.php/Main_Page) module is created for the [ansible](https://docs.ansible.com/) bare-metal-install collection [tuxifier](https://github.com/Geertsky/tuxifier).

It features the following:
* It depends on the [dracut-sshd](https://github.com/gsauthof/dracut-sshd) module, and on the dracut modules `network`, `mdraid` and `crypt`.
* It includes a `python` [conda](https://conda-forge.org/docs/) environment with support for [linux-system-roles.storage](https://github.com/linux-system-roles/storage) and some other basic tools in the initial ramdisk. By packaging a conda environment. (See: [python-nest](https://github.com/Geertsky/python-nest))
* It pauses the boot process just before the root filesystem gets mounted _(dracut `pre-mount` hook)_

This combination makes it possible to use [ansible](https://docs.ansible.com/) to:
* partition (a) disk(s)
* install an OS
* poweroff the machine<br>
or<br>
* continue the boot to the freshly installed OS and continue your ansible playbook from there.

## Where this fits

This repository is one of four that make up the tuxifier installer:

| Repository | Role |
|---|---|
| `dracut-incubator` (this one) | The dracut module that puts the packed python-nest environment in an initramfs and holds the boot until the install is done |
| [python-nest](https://github.com/Geertsky/python-nest) | The conda recipes and the environment that make up the python-nest environment |
| [tuxifier](https://github.com/Geertsky/tuxifier) | The ansible collection that runs inside that initramfs and installs the OS |
| [tuxifier-playbook](https://github.com/Geertsky/tuxifier-playbook) | An example playbook and inventory |

## How it works

1. The `dracut-incubator` module depends on and installs the `python-nest.squashfs` conda environment. The build system supplies the ssh host keys and the `authorized_keys` of the initramfs, see [SSH access](#ssh-access).
2. The machine boots the initramfs with its kernel. The network is brought up (`rd.neednet=1`) and `sshd` starts.
3. The `initqueue` hooks run. `defer-root-wait.sh` cancels the wait for the root device, which, possibly, does not exist yet. `mount-conda-squashfs.sh` mounts the squashfs read-only on `/local/conda/envs/python-nest`.
4. The `pre-mount` hook `wait_for_ansible_finished.sh` stops the boot. Every 5 seconds it writes a line to `/dev/console` with the uptime and the contents of `/tmp/message`, if that file exists.
5. Ansible connects over ssh as root and uses the python interpreter of the mounted environment to partition the disks and install the OS. [tuxifier](https://github.com/Geertsky/tuxifier) writes its progress to `/tmp/message`.
6. When the playbook is done it creates the file `/tmp/ansible-finished`. The boot continues. With `continue_install: false` tuxifier has installed a `pre-pivot` hook that powers the machine off. With `continue_install: true` the boot goes on into the installed system. See the `continue_install` variable of [tuxifier](https://github.com/Geertsky/tuxifier).
7. The `cleanup` hook `umount-python-nest.sh` unmounts the squashfs, and dracut mounts the root filesystem (`root=`) and switches to it.

The module is not enabled by default: it has to be requested with `-a incubator`.

## Installing the dracut-incubator module

* Clone this repository and copy or link the `dracut-incubator/94incubator` directory to the `/usr/lib/dracut/modules.d/` directory. The module is called `incubator`: dracut drops the number in front of the directory name.

* Download the pre-packaged [python-nest.squashfs](https://verweggistan.eu/python-nest.squashfs) <br>
and place it in `/usr/lib/dracut/modules.d/94incubator/`

**Or** <br>

* build and modify the `python-nest.squashfs` as described here: [python-nest](https://github.com/Geertsky/python-nest) <br>
and place it in `/usr/lib/dracut/modules.d/94incubator/`

Without the squashfs `dracut` stops with `Missing …/94incubator/python-nest.squashfs`.

## Building the initramfs

The initramfs image can be built using the following command:

```
sudo dracut -NM -a "incubator" incubator-initramfs-$(uname -r).img $(uname -r)
```

The build is not meant for a host-only initramfs, hence `-N`. Prebuilt images are listed in the [tuxifier-playbook](https://github.com/Geertsky/tuxifier-playbook) repository.

The `incubator` module pulls in the dracut modules below. They are needed to support the storage layouts of [linux-system-roles.storage](https://github.com/linux-system-roles/storage):

| dracut module | adds | enables |
|---------------|------|---------|
| `sshd`        | `sshd`, the ssh host keys and `authorized_keys` | Logging in from the Ansible controller |
| `network`     | The network configuration | `rd.neednet=1` and the `ip=` arguments |
| `crypt`       | The kernel modules and libraries for LUKS | LUKS encrypted volumes |
| `mdraid`      | `mdadm`, the md udev rules (`63-md-raid-arrays.rules`, `64-md-raid-assembly.rules`) and the `raid*` and `dm-raid` kernel modules | md RAID (`type: raid`, or `raid_level` on an `lvm` pool) and LVM RAID volumes |

`mdadm` has to be installed on the system the initramfs is built on. Without it `dracut` stops with `dracut module 'incubator' depends on 'mdraid', which can't be installed`. Without the md udev rules the storage role fails with `mdadm: /dev/vdX is busy - skipping`.

>[!NOTE]
>These modules only provide the tools in the initramfs used for the install. For the installed system the [tuxifier](https://github.com/Geertsky/tuxifier) role installs `cryptsetup` and `mdadm`, writes `/etc/crypttab` and `/etc/mdadm.conf` from the devices it created, and the kernel package builds the initramfs of the installed system, which selects the `crypt` and `mdraid` modules itself.

### SSH access

The `sshd` module copies the keys that give access to the initramfs from the system on which `dracut` runs. Without them nobody can log in, and `dracut` stops with `No authorized_keys for root user found!` or `Didn't find any SSH host key!`.

**authorized_keys.** The public keys that are allowed to log in as root. The first of these files that exists on the build system is used:

| Priority | File | Remarks |
|----------|------|---------|
| 1 | `/root/.ssh/dracut_authorized_keys` | Use this file to give the initramfs other keys than the root user of the build system. |
| 2 | `/etc/dracut-sshd/authorized_keys` | |
| 3 | `/root/.ssh/authorized_keys` | The default: the keys of the root user of the build system. |

This is the behavior of [dracut-sshd](https://github.com/gsauthof/dracut-sshd), see its documentation (the *Install* section and the FAQ) for the details. To change the keys, edit the file that is used, or create a file of higher priority, and build the initramfs again: the keys are copied into the image while it is built.

For example, to give the initramfs the key of an Ansible controller without touching the `authorized_keys` of root on the build system:

```
sudo sh -c 'umask 077; echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyOfTheController ansible@controller" >> /root/.ssh/dracut_authorized_keys'
sudo dracut -NM -a "incubator" incubator-initramfs-$(uname -r).img $(uname -r)
sudo lsinitrd incubator-initramfs-$(uname -r).img | grep authorized_keys
```

The `lsinitrd` line shows that `root/.ssh/authorized_keys` is in the image. A key can be in the image and still be refused when the root account is locked (`!`) in `/etc/shadow`; see the FAQ of dracut-sshd.

The `authorized_keys` of the initramfs are also added to the root user of the installed system by [tuxifier](https://github.com/Geertsky/tuxifier), together with the keys from its `root_authorized_keys` variable.

**Host keys.** The ssh host keys of the build system are copied into the image: `/etc/ssh/dracut_ssh_host_*_key` if they exist, otherwise `/etc/ssh/ssh_host_*_key`. Every machine booted from the image has that identity. Anyone who can read the image can read the private keys, and an ssh client that connected to another image from the same build system sees the same host key.

**sftp.** If the `sshd_config` of the initramfs has no `internal-sftp` subsystem, the module adds `Subsystem sftp internal-sftp` before the first `AcceptEnv` line, so that file transfers work without an `sftp-server` binary.

## Booting the incubator-initramfs
The initramfs file together with its kernel need to be fed to the server by any way possible. For instance: PXE, virt-manager Direct kernel boot, customized grub.

The image is large, about 240 MB, because it contains the squashfs with the python-nest environment. Give the machine enough memory: the test installs use 2 GiB.

### Required boot arguments

| kernel argument | description                                                                                                                                                                    |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|`rd.neednet=1`   |The initial ramdisk execution requires network accessibility. The network is configured by dracut, so the standard dracut `ip=` arguments apply.                               |
|`root=LABEL=root`|The `root` argument should be set to the device that contains the root filesystem after the install is finished. Use `LABEL=…` or a device path such as `/dev/vda2`. Other forms, such as `UUID=…`, are not supported: the wait for the device is only cancelled for these two.|
|`enforcing=0`    |`selinux` should be disabled during the install.                                                                                                                               |

### Console output

The progress messages of the wait loop are written to `/dev/console`. The kernel connects `/dev/console` to the device of the **last** `console=` argument of the kernel command line, when the arguments are of different device types. Kernel messages appear on all of them. Put the console you watch last, for instance `console=tty0 console=ttyS0` to receive the messages on the serial console. Without a `console=` argument there may be no output.

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| `dracut` stops with `Missing …/94incubator/python-nest.squashfs` | The squashfs is not in the module directory. | See [Installing the dracut-incubator module](#installing-the-dracut-incubator-module). |
| `dracut` stops with `module 'incubator' depends on 'mdraid', which can't be installed` | `mdadm` is not installed on the build system. | Install `mdadm` there. |
| `dracut` stops with `No authorized_keys for root user found!` or `Didn't find any SSH host key!` | The build system has no ssh keys for the initramfs. | See [SSH access](#ssh-access). |
| The machine boots, but ssh is refused with `Permission denied (publickey)` | The key you use is not in the `authorized_keys` that were copied into the image when it was built. | Add the key as described in [SSH access](#ssh-access) and build the initramfs again. |
| Ansible cannot connect | The network did not come up: `rd.neednet=1` is missing, or there is no dhcp or `ip=` configuration. | Check the boot arguments and the console. |
| The console shows `Missing Conda squashfs image` or `Could not mount … on /local/conda/envs/python-nest` | The squashfs is not in the image, or the kernel modules `loop` and `squashfs` are missing, for instance in a host-only image. | Build the initramfs as described above, without host-only. |
| No progress messages on the console | The messages go to the last `console=` argument, or there is none. | Put the console you watch last, see [Console output](#console-output). |
| The storage role fails with `mdadm: /dev/vdX is busy - skipping` | The md udev rules are missing. | Build with the `mdraid` module, which the `incubator` module pulls in. |

## License

This module is licensed under the [EUPL 1.2](LICENSE).
