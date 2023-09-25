ResetLocalStateOfs  = 0CA8h
SetTargetOfs        = 0CDCh
ExecuteCommandOfs   = 0E94h
SetDataAddressOfs   = 0F52h
Int13_DispatchOfs   = 12D8h
I13_DispatcherOfs   = 147Bh
Func_UnsupportedOfs = 14ABh
Func09_AlwaysOKOfs  = 17BAh
MyInt15Ofs          = 1910h
MyInt15InstallOfs   = 2D74h  ; Not really. This function is missing, but there
                             ; is a lot of empty space in the 284x BIOS
VersionOfs          = 4068h

PATCH_VERSION   MACRO
        ;db     "/2842VL BIOS v1.01 "
        db      " BIOS v2.0/EDD 1.1 "
                ENDM

INCLUDE aic7770.asm

END
