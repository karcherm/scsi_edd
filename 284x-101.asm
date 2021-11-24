ResetLocalStateOfs  = 0C80h
SetTargetOfs        = 0CB4h
ExecuteCommandOfs   = 0E6Bh
SetDataAddressOfs   = 0F29h
Int13_DispatchOfs   = 12B0h
I13_DispatcherOfs   = 1453h
Func_UnsupportedOfs = 1483h
Func09_AlwaysOKOfs  = 1792h
MyInt15Ofs          = 18E8h
MyInt15InstallOfs   = 2BB0h  ; Not really. This function is missing, but there 
                             ; is a lot of empty space in the 284x BIOS
VersionOfs          = 40A4h

PATCH_VERSION   MACRO
        ;db     "/2842VL BIOS v1.01 "
        db      " BIOS v1.01/EDD 1.0"
                ENDM

INCLUDE aic7770.asm

END
