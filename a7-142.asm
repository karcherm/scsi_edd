; Patch for ASPI7DOS.SYS, Version 1.42

; Copyright (C) 2021 Michael Karcher (the patch, not the ASPI driver itself)
; This patch may be used and distributed according to the MIT License.

.386  ; ASPI7DOS already contains 386 stuff, so allow it for the patch, too

BIOSDriveInfo STRUC
BD_IsMyDrive       db      ?
BD_TargetID        db      ?
BD_BusID           db      ?
BD_GeometryCX      dw      ?
BD_MaxLBA          dd      ?
BD_drive_type      db      ?
BD_GeometryDH      db      ?
BIOSDriveInfo ENDS

ASPI_CDBRequest STRUC
ASPI_FunctionNr    db      ?
ASPI_StatusCode    db      ?
ASPI_HbaID         db      ?
ASPI_ReqFlags      db      ?
ASPI_Rsvd          dd      ?
ASPI_TargetID      db      ?
ASPI_Lun           db      ?
ASPI_DataLen       dd      ?
ASPI_SenseLen      db      ?
ASPI_DataBufferPtr dd      ?
ASPI_NextReq       dd      ?
ASPI_cdblen        db      ?
ASPI_HaStatus      db      ?
ASPI_DevStatus     db      ?
ASPI_PostFunction  dd      ?
ASPI_PostDS        dw      ?
ASPI_SRBPtr        dd      ?
ASPI_Rsvd2         dw      ?
ASPI_SRBPhysical   dd      ?
ASPI_Rsvd3         db      22 dup (?)
ASPI_CDBdata       db      10 dup (?)
ASPI_CDBRequest ENDS

EDDData STRUC
EDDData_rqsize  dw ?
EDDData_count   dw ?
EDDData_ptr     dd ?
EDDData_LBAlow  dd ?
EDDData_LBAhigh dd ?
EDDData ENDS

CallerES = 2
CallerDS = 4
CallerDI = 6
CallerSI = 8
CallerDX = 10
CallerCX = 12
CallerBX = 14

DRIVER  SEGMENT USE16
        assume cs:DRIVER
        org 48FAh
I13R_CurrentDrive LABEL WORD
        org 48FDh
I13R_Flags LABEL BYTE
        org 4900h
I13R_ASPICall LABEL ASPI_CDBRequest
        org 4ACAh
I13_9_OK LABEL NEAR
        org 4BABh
I13_Unhandled LABEL NEAR
        org 4BB0h
I13_OutWithAHAndCarry LABEL NEAR
        org 4C10h
I13R_ExecuteRequest LABEL NEAR
        org 4C81h
I13R_DoneCallback LABEL NEAR
        org 4CEBh
I13R_SetStatus LABEL NEAR

        org 458Ah
        ; Big hole. It seems Adaptec reserved space for 88 BIOSDriveInfo
        ; structures instead of just 8 BIOSDriveInfo structures. So there
        ; are 80 superflous structures, i.e. 880 bytes.
Int13E_Dispatch LABEL WORD
        dw      OFFSET I13E_checkpresence       ; 41h
        dw      OFFSET I13E_read                ; 42h
        dw      OFFSET I13E_write               ; 43h
        dw      OFFSET I13E_verify              ; 44h
        dw      OFFSET I13_Unhandled            ; 45h (lock/unlock)
        dw      OFFSET I13_Unhandled            ; 46h (eject)
        dw      OFFSET I13E_seek                ; 47h
        dw      OFFSET I13E_params              ; 48h

MaybeI13E:
        sub     ah, 41h
        cmp     ah, 7
        ja      I13_Unhandled
        push    ax
        mov     al,ah
        mov     ah,0
        add     ax,ax
        mov     di,ax
        pop     ax
        jmp     cs:[di + Int13E_Dispatch]

I13E_checkpresence:
        push    bp
        mov     bp, sp
        mov     word ptr [bp+CallerBX], 0AA55h     ; extensions present
        mov     ah, 01h                            ; version 1.x
        mov     word ptr [bp+CallerCX], 1          ; support LBA disk calls only
        pop     bp
        jmp     I13_OutWithAHandCarry

I13E_params:
        mov     di, si
        push    ds
        pop     es
        mov     ax, 1Ah
        cmp     word ptr [di], ax
        jnb     go_on
        jmp     I13_Unhandled
go_on:
        stosw
        mov     ax, 1                   ; No 64K DMA limit, no CHS info
        stosw
        dec     ax
        mov     cx, 6
        rep     stosw                   ; clear CHS fields (not reporting them)

        push    eax
        mov     eax,0
        mov     dl,8
        mov     cx,ax
        mov     bx,925h
        push    es
        push    di
        clc
        call    MyCDBExecute
        pop     di
        pop     es
        pop     eax
        mov     eax, es:[di]
        xchg    ah,al
        rol     eax,16
        xchg    ah,al
        inc     eax
        stosd

        xor     ax, ax
        stosw                           ; high 32 bit of max LBA
        stosw
        mov     ax, 200h                ; sector size
        stosw
        jmp     I13_9_OK

I13E_read:
        mov     bx, 928h
        jmp     SHORT I13E_rwcommon
I13E_write:
        mov     bx, 112Ah
I13E_rwcommon:
        stc
        push    eax
        call    I13E_core
        pop     eax
        jmp     I13_OutWithAHandCarry

I13E_verify:
        mov     bx, 12Fh
        stc
        push    eax
        call    I13E_core
        pop     eax
kill_bad_fn:
        jnc     SHORT verify_done
        cmp     ah, 1
        jne     SHORT verify_done
        ; no fake verify yet.
        ; verify might very well be above 64KB, so Adaptecs idea to
        ; "read over the F000 segment" will fail
is_ok:
        mov     ah, 0
        clc
verify_done:
        jmp     I13_OutWithAHandCarry

I13E_seek:
        test    [I13R_flags], 1 ; implies CLC
        jnz     is_ok           ; ignore seek
        mov     bx, 12Bh
        push    eax
        call    I13E_core
        pop     eax
        jmp     kill_bad_fn     ; MUST change this when fake verify gets
                                ; implemented

I13E_core PROC NEAR
        mov     eax, [si+EDDData_LBAlow]
        mov     dl, 0
        mov     cx, word ptr [si+EDDData_Count]
        les     di, [si+EDDData_Ptr]

MyCDBExecute LABEL NEAR
        push    ds
        push    si
        push    cs
        pop     ds
        ASSUME  ds:DRIVER
        mov     si, OFFSET I13R_ASPICall
        mov     word ptr [si+ASPI_DataBufferPtr], di
        mov     word ptr [si+ASPI_DataBufferPtr+2], es

        sbb     di, di          ; CF set on entry: allow length
        and     di, cx
        xchg    di, cx
        add     di, di          ; sector count to 256-byte-count
        mov     byte ptr [si+ASPI_DataLen], dl
        mov     word ptr [si+ASPI_DataLen+1], di
        mov     byte ptr [si+ASPI_DataLen+3], 0
        xchg    ah,al
        ror     eax,16
        xchg    ah,al
        mov     dword ptr [si+ASPI_CDBdata+2], eax
        xchg    ch,cl
        mov     word ptr [si+ASPI_CDBdata+7], cx
        mov     [si+ASPI_FunctionNr], 2
        mov     [si+ASPI_ReqFlags], bh
        mov     [si+ASPI_CDBlen], 10
        mov     [si+ASPI_SenseLen], 14
        mov     [si+ASPI_CDBdata], bl
        mov     [si+ASPI_CDBdata+1], 0
        mov     [si+ASPI_CDBdata+6], 0
        mov     [si+ASPI_CDBdata+9], 0
        mov     word ptr [si+ASPI_PostFunction], OFFSET I13R_DoneCallback
        mov     word ptr [si+ASPI_PostFunction+2], cs

        mov     bx, [I13R_CurrentDrive]
        mov     al, [bx+BD_TargetID]
        mov     [si+ASPI_TargetID], al
        mov     al, [bx+BD_BusID]
        mov     [si+ASPI_HbaID], al
        mov     [si+ASPI_LUN], 0

        call    I13R_ExecuteRequest
        call    I13R_SetStatus
        pop     si
        pop     ds
        ret
I13E_core ENDP

        ; branch out before clobbering SI and DS
        org 4994h
        cmp     ah, 20h
        jbe     SHORT I13_Classic
        jmp     MaybeI13E
I13_Classic:
        mov     si, cs
        mov     ds, si

        org     53h
        ;db     "Version 1.42"
        db      "V1.42+EDD1.0"
        org     4FB5h
        db      "V1.42+EDD1.0"

DRIVER    ENDS
END
