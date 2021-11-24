; Patch for Adaptec's 274x BIOS, Version 2.11 to add (rudimentary) EDD support.
; SHA1 of expected input file: A0EC9AFE433549BB384E76A4167C2CB14BFE3FDA

MyInt15InstallOfs   = 0B4Bh
ResetLocalStateOfs  = 0BF4h
SetTargetOfs        = 0C28h
ExecuteCommandOfs   = 0DE1h
SetDataAddressOfs   = 0E9Fh
Int13_DispatchOfs   = 1224h
I13_DispatcherOfs   = 13BCh
Func_UnsupportedOfs = 13ECh
Func09_AlwaysOKOfs  = 16F4h
MyInt15Ofs          = 184Ah
VersionOfs          = 18D8h 

PATCH_VERSION   MACRO
        ;db     "Release"
        db      "EDD 1.0"
                ENDM

INCLUDE aic7770.asm

END
