Int13 Extension support for Adaptec BIOSes
==========================================

How to use it
-------------

This repository contains patches for Adaptec SCSI BIOSes and ASPI drivers (currently for the 2740 and 2840) to support the Phoenix/Microsoft Int13 extensions used to access hard disks above 8GB in LBA mode. To avoid potential copyright problems, this repository does not contain the actual Adaptec code. Instead, this repository contains an assembler source code file that generates an object file that contains only the locations that need to be overwritten to add Int 13 extension support to the respective files.

To apply the patch, you need the assembled form of the patch, which can be generated using MASM or a compatible assembler like Borland's TASM or JWASM. This patch has been tested to assemble correctly on both TASM and JWASM, even though TASM produces a different output because TASM defaults to single-pass mode and the patch contains a non-annotated short forward jump. Both assembled versions are functionally identical. You can also just download the latest GitHub release which includes an assembled object file.

To apply an object file as patch, my tool [omfpatch](https://github.com/karcherm/omfpatch) can be used. [Release 1.1](https://github.com/karcherm/omfpatch/releases/tag/v1.1) is known to work with this patch. You can choose to download either the DOS or the Win32 version of omfpatch depending on the system you want to use to apply the patch.

Patches for following SCSI BIOSes is included

Controller | Version | patch object | map file     | ROM chip size
-----------|---------|--------------|--------------|---------------
AHA-274x   |  2.11   | 274x-211.obj | bios16k.map  | 32KB (256kBit)
AHA-284x   |  1.01   | 284x-101.obj | bios1632.map | 64KB (512kBit)

Furthermore, a patch for the following ASPI driver is included

Driver       | Version | patch object | map file   | file size
-------------|---------|--------------|------------|------------
ASPI7DOS.SYS | 1.42    | a7-142.obj   | a7-142.map | 36160 bytes

Note that the latest 274x BIOS (2.11) seems to not be available for download from the Adaptec / MicroSemi. Their page has version 2.10. This patch *does not apply to version 2.10*. You can obtain the ROM image by reading it from an controller that has the latest version. The ROM chip is an OTP chip labelled `549306-00 D BIOS 7D00 (c) 1993`.

You can run `omfpatch 274x-211.bin bios16k.map 274x-211.obj` to create a patched BIOS image for the 2740.
You can run `omfpatch 284x-101.bin bios1632.map 284x-101.obj` to create a patched BIOS image for the 2840.

The patched BIOS identifies itself as "2.11 EDD 1.0" instead of just "2.11 Release" to indicate the *extended disk drive* specification.

Disclaimer
----------

If you patch your BIOS and something goes wrong, the computer may become unbootable. It is recommended that you have a way to recover your BIOS, like an external flasher connected to a different computer. Make a backup of your BIOS before your install a patched BIOS.
