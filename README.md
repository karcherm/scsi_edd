Int13 Extension support for Adaptec BIOSes
==========================================

How to use it
-------------

This repository contains patches for Adaptec SCSI BIOSes (currently only the 2740, more to come) to support the Phoenix/Microsoft Int13 extensions used to access hard disks above 8GB in LBA mode. To avoid potential copyright problems, this repository does not contain the actual Adaptec BIOSes. Instead, this repository contains an assembler source code file that generates an object file that contains only the locations that need to be overwritten to add Int 13 extension support to the respective BIOS images.

To apply the patch, you need the assembled form of the patch, which can be generated using MASM or a compatible assembler like Borland's TASM or JWASM. This patch has been tested to assemble correctly on both TASM and JWASM, even though TASM produces a different output because TASM defaults to single-pass mode and the patch contains a non-annotated short forward jump. Both assembled versions are functionally identical. You can also just download the latest GitHub release which includes an assembled object file.

To apply an object file as patch, my tool [omfpatch|https://github.com/karcherm/omfpatch] can be used. [Release 1.1|https://github.com/karcherm/omfpatch/releases/tag/v1.1] is known to work with this patch. You can choose to download either the DOS or the Win32 version of omfpatch depending on the system you want to use to apply the patch. The latest 274x BIOS (2.11) seems to not be available for download from the Adaptec / MicroSemi. Their page has version 2.10. This patch *does not apply to version 2.10*. You can obtain the ROM image by reading it from an controller that has the latest version. The ROM chip is an OTP chip labelled `549306-00 D BIOS 7D00 (c) 1993`.

You can run `omfpatch 274x-211.bin bios16k.map 274x-211.obj` to create a patched BIOS image.

The patched BIOS identifies itself as "2.11 EDD 1.0" instead of just "2.11 Release" to indicate the *extended disk drive* specification.

Disclaimer
----------

If you patch your BIOS and something goes wrong, the computer may become unbootable. It is recommended that you have a way to recover your BIOS, like an external flasher connected to a different computer. Make a backup of your BIOS before your install a patched BIOS.
