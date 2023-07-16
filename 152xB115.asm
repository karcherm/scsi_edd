; Copyright (C) 2023 Michael Karcher (the patch, not the original BIOS!)
; This patch may be used and distributed according to the MIT License.

; INTRODUCTION
; ------------

; This assembler file generates an object file that can be used to patch
; the Adaptec 1520B/1522B BIOS version 1.15 to add support for hard disks
; with a capacity above 8GB. It does so by implementing the required part
; of the Enhanced Disk Drive specification, version 1.0.

; The patch is to be applied using an open source tool called OMFPATCH,
; which is also written by Michael Karcher

; This code is inspired by an earlier patch for the AIC-7770 BIOS
; (Adaptec 2742 / 2842).


; PREREQUISITES
; -------------

; The BIOS uses 80286-type instructions (PUSHA, PUSH imm, SHL/SHR with a
; non-1 constant), INSW, OUTSW, so this patch can use them, too.
; Performance of the 152xB controllers in XT-based computers would be poor
; anyway, as they seem to no longer support DMA, and running IN/STOSB in
; a loop is dead slow on an 8088.
.286


; CHAPTER 1: The stack frame during INT13 execution
; -------------------------------------------------

; The Adaptec INT13 handler sets up a stack frame:

; 32 bytes contain a ASPI-like SCSI request block. BP points to this block.
; If an Adaptec ASPI driver is loaded, the BIOS passes this request block to
; the ASPI driver (through a proprietary interface between the BIOS and the
; ASPI driver - NOT as a standard ASPI application); if no ASPI driver is
; loaded, the BIOS uses an internal implementation of the ASPI function
; "execute SCSI I/O command". BP points to this block. The last byte of This
; block is at [bp+1Fh] and contains the high byte of the I/O base address,
; i.e. 01 for an 1522B at 0140h or 03 for an 1522B at 340h. This byte is
; used by the internal "execute SCSI command" implementation to address the
; adapter.

; below the SCSI request block (i.e. at negative offsets relative to BP), all
; relevant caller registers except for AX are saved (BP is not saved here, as
; it is used for stack framing instead of parameter passing; also SS and cs
; are not saved becasue the stack is never switched and CS is saved as part of
; the IRET/RETF return address.

; negative offsets to BP, can't be struct members
CallerBX = -2
CallerCX = -4
CallerDX = -6
CallerSI = -8
CallerDI = -10
CallerDS = -12
CallerES = -14
; non-negative offsets to BP
BIOSFrame STRUCT
AlwaysTwo       db  ?       ; ASPI function number (2 = execute SCSI I/O)
BusStatus       db  ?       ; Host adapter status code according to ASPI
                            ; specification
DevStatus       db  ?       ; Device status according to SCSI specification:
                            ; The byte received in the "STATUS IN" phase.
TargetId        db  ?       ; ID in top 3 bits
BufferSeg       dw  ?       ; Yes, really: segment before offset. Whatever.
BufferOfs       dw  ?
TransferCount   dw  ?
TransferCountHi db  ?
CDBLen          db  ?
CDB             db  10 dup(?)
BIOSFrame ENDS

; For some SCSI requests, the part of the request block starting at
; TransferCount is re-used as buffer. For example, this is used for the SCSI
; commands "READ CAPACITY" and "REQUEST SENSE".
InternalBuffer = TransferCount

; CHAPTER 2: Variables stored in the BIOS data area
; -------------------------------------------------

; The Adaptec BIOS reuses the temporary memory area in the BIOS data segment
; at 40:42, which is used by the floppy disk BIOS implementation to store the
; status bytes received from the NEC 765-compatible floppy controller. Those
; bytes are only used by the BIOS during execution of floppy disk functions,
; and might be examined by certain low-level applications immediately after a
; floppy disk function returns. This means they are definitely *not* in use
; while INT13 is executing a hard drive function.

; DOS multitasking implementations that try to run a hard disk INT13 and a 
; floppy disk INT13 at the same time for different tasks will not work with the
; Adaptec 152xB BIOS. Most likely, other hard disk BIOS implementations behave
; similar, and no serious multitasking implementation relies on being able to
; run the hard disk BIOS and the floppy disk BIOS at the same time without
; virtualizing the BIOS data area.

BIOSDATA SEGMENT AT 40h
        org 42h
SCSI_command    db  ?       ; SCSI command to be written into the CDB by the
                            ; generic CDB setup functions.
SCSI_drive      db  ?       ; SCSI ID of the target drive.
SCSI_offset     dw  ?       ; offset of the SCSI data transfer buffer. the
                            ; segment of that buffer is kept in ES, so there
                            ; is no need to store it in the BIOS data area.
BIOSDATA ENDS


; This segment represents the 16KB runtime BIOS of the 1520/1522 controller.
; All bytes emitted into this segment will replace the original BIOS bytes.

MAIN    SEGMENT
        ; The Adaptec Int13 implementation (which will be extended, not
        ; replaced) initializes DS to the BIOS data segment 40h, so tell the
        ; assembler that those variables may be accessed without generating
        ; segment prefixes.
        ASSUME cs:MAIN, ds:BIOSDATA

; CHAPTER 3: Importing lower-level functions
; ------------------------------------------

; These functions are internal functions of the Adaptec 152xB BIOS. They are
; very useful building blocks to implement INT13 services on top of them.
; They are used by the standard INT13 services provided by Adaptec, and will
; be used for the extended BIOS functions as well.


; INPUT:
;   AL            : sector count
;   [SCSI_drive]  : SCSI ID
;   [SCSI_offset] : buffer offset
;   [SCSI_command]: 10-byte command (2F=verify, FF=fake verify)
;   DX:CX         : LBA
;   ES            : buffer segment
; OUTPUT:
;   [bp+xxh]      : SCSI command block filled
;
        org     19E0h
SetupSectorAddressCommand LABEL NEAR

; INPUT:
;   [bp+xxh]      : SCSI command block
; OUTPUT:
;   AH            : BIOS status code
;   CF            : go/no-go flag
        org     15A6h
RunSCSIRequest            LABEL NEAR

; INPUT:
;   DL                 : SCSI ID
; OUTPUT:
;   AH                 : BIOS status code
;   CF                 : Set on error
;   [bp+InternalBuffer]: 32 bit max sector nr; 32 bit sector size (big endian)
;                        (on success only)
        org     0E6Fh
ReadCapacity              LABEL NEAR

; CHAPTER 4: Importing labels in the original Int13 implementation
; ----------------------------------------------------------------

; These lables can be to jumped to when no further special processing is
; required.

; Exits the current INT13 call with carry flag set and AH=1 ("function not
; implemented"). It chains into Int13_ExitWithStatus
        org     0F45h
Int13_Unsupported         LABEL NEAR

; Exits the current INT13 call. AH and CF are to be set before getting here.
; The value of AH is stored to 40:74, and can be retrieved by INT13, AH=1
; later.
        org     0F4Eh
Int13_ExitWithStatus      LABEL NEAR

; Exits the current INT13 call. AH and CF are to be set before getting here.
; The status at 40:74 is NOT updated.
        org     0F4Eh
Int13_Exit                LABEL NEAR

; Executes a read or write operation. At this address, the ASPI-inspired
; request block at BP already needs to be completely set up.
; There is a call to RunSCSIRequest at this location (so see there for
; input parameters), and then the result (already a BIOS status code) is
; returned to the caller, possibly saving it in 40:74
        org     0F9Fh
Int13_RWAfterSetup        LABEL NEAR

; CHAPTER 5: Patching the dispatch code of the Adaptec Int13 entry points
; -----------------------------------------------------------------------

; The BIOS provides four different possible INT13 entry points. Each entry
; point hard-codes the base address (340h or 140h) of the controller. So the
; four entry points are actually two pairs of entry points. One set of entry
; points is used when the Adaptec controller provides drive 80h (and
; possibly 81h too). This set of entry points is called "With80". The second
; set of entry points is used when the Adaptec controller only provides drive
; 81h, and chains drive 80h to the vector found in INT13 when the Adaptec
; BIOS was initialized. This set of entry points is called "Pass80".

; The Adaptec BIOS never provides drive numbers above 81h.

; "With80" set of entry points
I13EntryWith80_At140 = 856h         ; Address of handler for IO base 140h
I13EntryWith80_At340 = 8E3h         ; Address of handler for IO base 340h
I13EntryWith80_Dispatch = 970h      ; Address of common dispatch table

; "Pass80" set of entry points
I13EntryPass80_At140 = 99Ch         ; Address of handler for IO base 140h
I13EntryPass80_At340 = 0A20h        ; Address of handler for IO base 340h
I13EntryPass80_Dispatch = 0AA4h     ; Address of common dispatch table

; The dispatch tables are mostly identical, but provided different handlers
; for function 00 (reset), function 06 (format track with interleave/bad
; sector mapping) and function 0D (alternate reset). The difference between
; 00 and 0D is that 00 generally resets all drives, whereas 0D only resets
; hard drives. If 80 is not on adaptec, the handler for 0D forwards the reset
; request to the BIOS that provides drive 80 (possibly on-board IDE).
; Function 06 (format track) is not supported for SCSI, as SCSI drives
; usually do not allow trackwise formatting, but Adaptec implements extended
; control functions at this API. If 80h is not on adaptec, forwarding to the
; classic formatting code is performed if DL=80.

; The two entry points of for the different base address only differ in a
; single byte, setting [bp+1Fh] to 01 or 03 for 140h or 340h. The instruction
; after initializing the I/O base address is the bounds check for AH
; (The Adaptec BIOS supports dispatching the functions 00..15h). This is
; exactly where extended INT13 calls are rejected.

; This defines the offset of the common part between the 140 and 340 handlers
; in each set of entry points. That is the distance between the entry itself
; and the instruction after the instruction initializing [bp+1Fh].

I13EntryWith80_CommonPartOfs = 033h
I13EntryPass80_CommonPartOfs = 051h

; The implementation of the extension of the dispatch algorithm is shown
; next. It is defined as a macro, so it can be invoked for both set of
; entry points.

ExtendDispatch MACRO set
; 1. The 140h entry code and the 340h entry codes and then the dispatch table
;    are laid out consecutively after each other in the BIOS ROM.
; 2. If the instruction after initializing the I/O base for the 340h entry is
;    patched to a backwards jumps into the 140h entry, some space gets freed.
;    In the "With80" case, the jump instruction would be at 916h
;    (I13EntryWith80_At340 + I13EntryWith80_CommonPartOfs) and as the
;    instruction is 3 bytes long, this would free up the space 919h to 970h
;    (57h / 87 bytes total). Similarly, in the "80 not on Adaptec" case, the
;    jump instruction would be at A71h, so A74h to AA4h will be unused.
;    (30h / 48 bytes total).

        org I13Entry&set&_At140 + I13Entry&set&_CommonPartOfs
I13Entry&set&_Common LABEL NEAR         ; Common code starts here

        org I13Entry&set&_At340 + I13Entry&set&_CommonPartOfs
        jmp I13Entry&set&_Common        ; Jump into first copy of common code
I13Entry&set&_MaybeEDD LABEL NEAR       ; Space for the EDD dispatcher
                                        ; (see bullet point 6)

; 3. As already mentioned, the common code starts with checking that AH
;    is in the range 00..15 (which is handled by the Adaptec Int13 handler)
;    In case the AH value is out-of-bounds, a NEAR jump at Common+5 is
;    is executed. In case the AH value is OK can can be used to index the
;    jump table, execution flows past this jump, i.e. to Common+8.

        org I13Entry&set&_At140 + I13Entry&set&_CommonPartOfs + 5
        jmp     I13Entry&set&_MaybeEDD
I13Entry&set&_ValidAH:

; 4. As the now unused space is directly before the dispatch table, the
;    dispatch table can be enlarged. The extended disk drive specification
;    requires 8 entries for the functions 41h to 48h, that is 16 bytes,
;    as each entry is a 16-bit offset in the BIOS segment.
; 5. The current dispatch code interprets AH as an unsigned number. This
;    would only allow extending the table towards higher addresses. As the
;    free space is before the table, this would require moving the whole
;    table. The dispatch code can be patched though, to use
;    signed number dispatching, allevating the need to move the table:

        ; The AL extension code is near the end of the entry-specification
        ; prologue (after checking DL validity and remapping BIOS drive
        ; numbers to SCSI IDs). This end is identical for the With80 and
        ; Pass80 sets. The dispatch code of the first entry (_140) in
        ; each set is used, so the very end of that code is at the start
        ; of the second entry (_340). The AL extension code is 0Eh bytes
        ; before the very end:
        org I13Entry&set&_At340 - 0Eh
        ; originally XOR AH,AH (2 bytes)
        cbw                             ; 1 byte
        nop                             ; 1 extra padding byte

; 6. The extended INT13 functions codes should 41h to 48h get remapped to
;    F8h to FFh (by subtracting 49h). This will be dispatched as table
;    index -8 to -1. The table extension consumes 16 bytes of the free
;    space in both parts, so the remaining areas are 71 bytes and 32 bytes.
;    Even 32 bytes should be enough to implement remapping.

        org     I13Entry&set&_MaybeEDD
        sub     ah, 49h
        jb      I13Entry&set&_MaybeOK   ; function below 49h may be I13E
I13Entry&set&_unsupported:
        jmp     Int13_Unsupported       ; otherwise, bad function indeed
I13Entry&set&_MaybeOK:
        cmp     ah, 0F8h                ; 0F8h is remapped 41h
        jb      I13Entry&set&_unsupported  ; local target to get a short JMP
        jmp     I13Entry&set&_ValidAH

;    Counting bytes (e.g. by looking at a list file, or knowing the 8086
;    instruction set) shows that this dispatching code takes 16 bytes, So
;    it fits the ranges of 71 and 32 bytes quite well, leaving 55 / 16 bytes
;    remaining hole size.

; 7. The current position marks the start of the remaining hole. Especially
;    the 55 byte hole can be re-used for a different purpose (see below).
I13Entry&set&_EndEDDDispatch:

; 8. Finally, the dispatch table needs to be extended:
        org I13Entry&set&_Dispatch - 16
        dw      OFFSET I13E_checkpresence       ; 41h
        dw      OFFSET I13E_rw                  ; 42h
        dw      OFFSET I13E_rw                  ; 43h
        dw      OFFSET I13E_verify              ; 44h
        dw      OFFSET Int13_Unsupported        ; 45h (lock/unlock)
        dw      OFFSET Int13_Unsupported        ; 46h (eject)
        dw      OFFSET I13E_seek                ; 47h
        dw      OFFSET I13E_params              ; 48h
ENDM

; This macro needs to be invoked twice: Once for the "With80" set of
; entry points and a second time for the "Pass80" set of entry points:
        ExtendDispatch With80
        ExtendDispatch Pass80

; CHAPTER 6: Implementing the extended INT13 functions
; ----------------------------------------------------

; SECTION 6.1: Enhanced Disk Drive presence check

; The presence check of the INT13 extension function is very simple. the
; Int13 entry code before the function dispatcher already validates that DL
; refers to a drive handled by the Adaptec BIOS, so no further checks are
; needed. This makes the code short enough to fit into the 55 byte hole
; after the EDD dispatcher for the "With80" case.
        org     I13EntryWith80_EndEDDDispatch
I13E_checkpresence:
        mov     [WORD PTR bp+CallerBX], 0AA55h  ; extensions present
        mov     ah, 01h                         ; Version 1.0
        mov     [WORD PTR bp+CallerCX], 1       ; support LBA disk calls only
        clc
        jmp     Int13_Exit

; The remaining functions will get placed into padding bytes originall filled
; with 0FFh
        org     03E50h

; SECTION 6.2: Get drive parameters
        
; The "get drive parameters" function is used to retrieve the total number of
; sectors on the drive. The remaining fields of the parameter block are
; either constant (like the sector size, which is fixed to 512 bytes) or
; not implemented (like "native" CHS parameters).
I13E_params:
        mov     es, [bp+CallerDS]
        mov     di, [bp+CallerSI]
        mov     ax, 1Ah                 ; size of parameter block in EDD 1.0
        cmp     es:[word ptr di], ax    ; check provided buffer size
        jnb     go_on
        jmp     Int13_Unsupported       ; buffer too small
go_on:
        stosw                           ; set result data size
        mov     ax, 1                   ; No 64K DMA limit, no CHS info
        stosw
        dec     ax
        mov     cx, 6
        rep     stosw                   ; clear CHS info (CHS not inplemented)
        push    es
        push    di
        call    ReadCapacity            ; requires SCSI ID (0/1) in DL
                                        ; CF/AH receives status
        pop     di
        pop     es
    
        jc      param_error
        mov     ax, [bp+InternalBuffer+2] ; translate big endian to little
                                        ; endian, also add 1 to get to "sector
                                        ; count" from "max LBA".
        xchg    ah, al
        add     ax, 1                   ; we need CF, don't use INC!
        stosw
        mov     ax, [bp+InternalBuffer]
        xchg    ah, al
        adc     ax, 0
        stosw
        xor     ax, ax                  ; clear AX and carry
        stosw                           ; high 32 bit of max LBA
        stosw
        mov     [WORD PTR es:di], 200h  ; sector size
param_error:
x_Int13_ExitWithStatus:
        jmp     Int13_ExitWithStatus

; SECTION 6.3 A generic helper function

; This function is a generic core to prepare an SCSI request packet based on
; a Disk Address Packet (according to the Enhanced Disk Drive specification).

; This function must be called with the stack in the same state as it was
; provided to the subfuction handler by the INT13 dispatcher, because it
; directly jumps into the INT13 cleanup code if the Disk Address Packet is
; invalid.

; This function fakes a requested sector count of zero (no matter what the
; request packet specifies) if the carry flag is clear on entry. This enables
; support for "seek" which does not transfer any data and does not require
; a sector count in the SCSI command.
; Thus the caller IS REQUIRED to set the carry flag if the sector count is
; to be honored.
; For "verify", even the fake "verify", the low-level functions used by
; I13E_setup understand that no data is going to be transferred, even if the
; sector count is non-zero. The number of sectors to be verified still needs
; to be passed to the drive, so VERIFY also requires CF to be set on entry.

; INPUT:
;   AL        : SCSI command (FF = fake verify)
;   DL        : SCSI ID of target drive
;   CF        : force sector count zero (for seek) if clear
;             : allow any sector count (read/write/verify) if set
;   [CallerSI]: offset of Disk Address Packet
;   [CallerDS]: segment of Disk Address Packet
; OUTPUT:
;   [bp+xxh]  : SCSI command block filled
;   DI        : clobbered
; EXCEPTION:
;   return address popped and JMP to Int13_Unsupported if the 
;   Disk Address Packet is bad.

I13E_setup PROC NEAR
        sbb     di, di
        mov     [SCSI_command], al
        mov     [SCSI_drive], dl
        mov     es, [bp+CallerDS]
        mov     si, [bp+CallerSI]
        cmp     [WORD PTR es:si], 10h
        jb      bad_fn                  ; request packet too small
        mov     ax, [WORD PTR es:si+2]
        and     ax, di
        cmp     ax, 7Fh
        ja      bad_fn                  ; too many sectors requested
        mov     bx, [es:si+4]
        mov     [SCSI_offset], bx
        mov     cx, [es:si+8]
        mov     dx, [es:si+0Ah]
        mov     es, [es:si+6]
        call    SetupSectorAddressCommand
        ret
bad_fn:
        pop     ax                      ; pop return address
        jmp     Int13_Unsupported       ; jump to standard error path
I13E_setup ENDP

; SECTION 6.4 Read, Write and Seek

; All of these calls build a 10-byte CDB containing the LBA, sendm that to
; the hard drive and translate the SCSI status or sense information into a
; BIOS status code.

; For seek, the sector count in the Disk Address Packet is ignored by clearing
; CF before entering I13E_Setup

I13E_rw:
        mov     al, ah
        add     al, al                  ; read -> F9+F9 = F2
                                        ; write -> FA+FA = F4
        add     al, 28h - 0F2h          ; F2 -> 28; F4 -> 2A; STC
I13E_rws_common:
        call    I13E_setup
        call    RunSCSIRequest
        jmp     I13E_HandleStatus

I13E_seek:
        mov     al, 2Bh
        clc
        jmp     I13E_rws_common


; SECTION 6.5: verify

; This is a special one. While verify is a mandatory INT13 function, and
; omitting support for this function will make a lot of applications fail,
; verify is an optional SCSI for command for disk drives. This code fragment
; re-implements the algorithm used for CHS verify, too: First, the optional
; VERIFY(10) command is attempted. If it succeeds, the function is done. if
; it fails referring to media or controller failures, the function is done,
; too. But if VERIFY(10) fails by getting the VERIFY(10) command rejected,
; the target is likely one of the disk drives not implementing VERIFY(10).

; In that case, the code falls back to sending READ(10), and setting the
; transfer buffer size to 0. The SCSI command execution logic will detect
; an unexpected DATA IN phase in this case, and the bus error recovery logic
; will just drop the data that is returned from the drive without storing it
; anywhere. Finally, the function will return the BIOS error code 8 (DMA
; overrun), which does *not* indicate any kind of error in case of mis-using
; READ to perform VERIFY.

I13E_verify:
        mov     al, 2Fh                 ; VERIFY(10)
        stc
        call    I13E_setup
        call    RunSCSIRequest
        jnc     I13E_HandleStatus       ; verify succeeded
        cmp     ah, 1                   ; BIOS status code: "function not
                                        ; supported". Returned if the drive
                                        ; rejected the command
verify_is_bad:
        stc                             ; restore CF indicating error
        jne     I13E_HandleStatus       ; verify failed, but not due to
                                        ; "function not supported"
        mov     al, 0FFh                ; fake SCSI VERIFY (READ without data)
        call    I13E_setup              ; carry still set from STC
        call    RunSCSIRequest
        jnc     I13E_HandleStatus       ; No "overrun" - likely cound was 0
        cmp     al, 8                   ; BIOS: "DMA overrun". As we executed
                                        ; READ but didn't expect data,
                                        ; excessive data sent by the drive
                                        ; is expected.
        je      verify_is_ok
        jmp     verify_is_bad
verify_is_ok:
        xor     ah, ah                  ; clears carry, too
        ; fallthrough into I13E_HandleStatus
        
; SECTION 6.6: Status handling

; If INT13 returns with carry set on a call that got a Disk Address Packet,
; the sector count field is to be updated to contain the number of sectors
; that were processed successfully before the error occurred. This code does
; not try to be smarter than the non-EDD 152xB BIOS implementation and thus
; does not try to calculate the number of successfully handled sectors from
; the SCSI residual count or comparing a sense LBA to the requested LBA, but
; it always blindly returns "zero sectors OK" in case of an error.

I13E_HandleStatus:
        jnc     is_ok
        mov     es, [bp+CallerDS]
        mov     si, [bp+CallerSI]
        mov     BYTE PTR [es:si+2], 0   ; report "zero sectors OK" in case
                                        ; of error
is_ok:
        jmp     Int13_ExitWithStatus


; CHAPTER 7: Version Number printed on boot
; -----------------------------------------

        org     3644h
        db      'E'         ; "1.15 " to "1.15E"

MAIN ENDS
END
