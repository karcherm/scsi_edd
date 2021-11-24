; Patch for Adaptec's 274x BIOS, Version 2.11 to add (rudimentary) EDD support.
; SHA1 of expected input file: A0EC9AFE433549BB384E76A4167C2CB14BFE3FDA

; Copyright (C) 2021 Michael Karcher (the patch, not the original BIOS!)
; This patch may be used and distributed according to the MIT License.

.286

BIOSFrame STRUC
we_dont_care_1  db       4 dup (?)
VDSFlags        db      ?
we_dont_care_2  db      11 dup (?)
CDBlen          db      ?
we_dont_care_3  db       7 dup (?)
CDBdata         db      12 dup (?)
we_dont_care_4  db       4 dup (?)
TransferLenLow  dw      ?
TransferLenHigh dw      ?
we_dont_care_5  db       8 dup (?)
BIOSFlags       dw      ?
we_dont_care_6  db       6 dup (?)
CallerAX        dw      ?
CallerBX        dw      ?
CallerCX        dw      ?
CallerDX        dw      ?
CallerSI        dw      ?
CallerDI        dw      ?
CallerDS        dw      ?
CallerES        dw      ?
BIOSFrame ENDS

IsNoData = 8    ; Flag for execution unit that this is a "no data" command
BF_IgnoreSeek = 80h

MAIN    SEGMENT
        assume cs:MAIN

        org 0BF4h
ResetLocalState LABEL NEAR
        org 0C28h
SetTarget LABEL NEAR
        org 0DE1h
ExecuteCommand LABEL NEAR
        org 0E9Fh
SetDataAddress LABEL NEAR

        org 13ECh
Func_Unsupported LABEL NEAR
        org 13EEh
I13FinishWithAH  LABEL NEAR

        org 16F4h
Func09_AlwaysOK LABEL NEAR

        org 1224h + 12h * 2
        ; remap functions 12..14 ("always OK") to function 09 ("always OK")
        ; this frees up 13E4..13E8
        dw      OFFSET Func09_AlwaysOK
        dw      OFFSET Func09_AlwaysOK
        dw      OFFSET Func09_AlwaysOK

        org 1224h
Int13_Dispatch LABEL WORD

        org 13BCh
        mov     al, BYTE PTR [bp+CallerAX+1]  ; originaly whole word to AX
        ;mov    bx, [bp+CallerBX] ; superflous, BX is already set
        mov     cx, [bp+CallerCX]
        mov     dx, [bp+CallerDX]
        push    40h
        pop     ds
        cbw
        mov     di, ax
        shl     di, 1
        cmp     al, 15h
        ja      short MaybeI13E
        mov     ax, [bp+CallerAX]
        jmp     cs:[di + Int13_Dispatch]
MaybeI13E:
        sub     al, 41h
        cmp     al, 7
        ja      Func_Unsupported
        mov     es, [bp+CallerDS]
        jmp     cs:[di - 41h*2 + Int13E_Dispatch]

        org 0B4Bh
Int13E_Dispatch LABEL WORD
        dw      OFFSET I13E_checkpresence       ; 41h
        dw      OFFSET I13E_read                ; 42h
        dw      OFFSET I13E_write               ; 43h
        dw      OFFSET I13E_verify              ; 44h
        dw      OFFSET Func_Unsupported         ; 45h (lock/unlock)
        dw      OFFSET Func_Unsupported         ; 46h (eject)
        dw      OFFSET I13E_seek                ; 47h
        dw      OFFSET I13E_params              ; 48h
I13E_checkpresence:
        mov     [bp+CallerBX], 0AA55h              ; extensions present
        mov     byte ptr [bp+CallerAX + 1], 01h    ; version 1.x
        mov     [bp+CallerCX], 1                   ; support LBA disk calls only
        jmp     Func09_AlwaysOK

I13E_params:
        mov     di, si
        mov     ax, 1Ah
        cmp     es:[word ptr di], ax
        jnb     go_on
        jmp     Func_Unsupported
go_on:
        stosw
        mov     ax, 1                   ; No 64K DMA limit, no CHS info
        stosw
        dec     ax
        mov     cx, 6
        rep     stosw                   ; clear CHS fields (not reporting them)
        push    es
        push    di
        call    ResetLocalState
        call    SetTarget
        mov     [bp+CDBdata], 25h    ; SCSI read capacity
        mov     [bp+CDBlen], 0Ah
        mov     [bp+TransferLenLow], 8
        mov     [bp+TransferLenHigh], 0
        and     [bp+VDSFlags], not IsNoData
        pop     bx                      ; address of LBA count.
                                        ; if the command succeeds, the low 32 bits are set to the
                                        ; capacity of the drive (-1), the high 32 bits are the sector size.
                                        ; it's big endian, though :(
        push    bx
        call    SetDataAddress
        call    ExecuteCommand
        pop     di
        pop     es
        push    ax
        mov     ax, es:[di]
        xchg    ah, al
        xchg    ax, es:[di+2]
        xchg    ah, al
        add     ax, 1                   ; from max_lba to sector count
        mov     es:[di], ax
        adc     es:[word ptr di+2], 0
        add     di, 4

        xor     ax, ax
        stosw                           ; high 32 bit of max LBA
        stosw
        mov     ax, 200h                ; sector size
        stosw
        pop     ax
        jmp     I13FinishWithAH

        org     184Ah
I13E_common_stc:
        stc
I13E_common:
        sbb     dx,dx
        call    ResetLocalState
        or      [bp+VDSFlags], ch
        mov     [bp+CDBdata], cl
        mov     [bp+CDBlen], 0Ah
        mov     ax, es:[si+2]
        and     dx, ax
        xchg    dh, dl
        mov     word ptr [bp+CDBdata + 7], dx        ; length to target
        add     ax, ax
        mov     word ptr [bp+TransferLenLow + 1], ax ; transfer length
        ; set LBA (bswapping it)
        mov     ax, es:[si+8]
        xchg    ah, al
        mov     word ptr [bp+CDBdata + 4], ax
        mov     ax, es:[si+10]
        xchg    ah, al
        mov     word ptr [bp+CDBdata + 2], ax
        test    [bp+VDSFlags], IsNoData
        jnz     no_data
        les     bx, es:[si+4]
        call    SetDataAddress
no_data:
        call    ExecuteCommand
        cmp     ah, 1                   ; unsupported command
        jne     usual_case
        test    [bp+VDSFlags], IsNoData
        jz      usual_case
return_ok:
        mov     ah, 0                   ; non-data command: verify or seek; deemed optional
                                        ; remap "unsupported" to OK
usual_case:
        jmp     I13FinishWithAH


I13E_read:
        mov     cx, 0028h
        jmp     I13E_common_stc
I13E_write:
        mov     cx, 002Ah
        jmp     I13E_common_stc
I13E_verify:
        mov     cx, 082Fh
        jmp     I13E_common_stc
I13E_seek:
        test    byte ptr [bp+BIOSFlags], BF_IgnoreSeek  ; TEST always clears CF
        jnz     return_ok
        mov     cx, 082Bh
        jmp     I13E_common

        org     18D8h
        db      "EDD 1.0"

MAIN    ENDS
END
