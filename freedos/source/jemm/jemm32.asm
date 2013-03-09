;*****************************************************************************
;** This is the main 32bit ASM part of JEMM.
;**
;** JEMM contains code of FreeDOS Emm386, which in turn used the source of
;** an EMM made public in c't (a german IT magazine) in 08/90, page 214,
;** written by Harald Albrecht.
;**
;** some parts the code which is based on FD Emm386 is copyright protected and
;** licensed under the Artistic License version (see LICENSE.TXT for details).
;**
;** 1. EMS 3.2 functions (file EMS32.INC)
;**   (c) 1990       c't/Harald Albrecht
;**   (c) 2001-2004  tom ehlert
;** 2. DMA support (file DMA.ASM)
;**   (c) 1990       c't/Harald Albrecht
;** 3. privileged opcode emulation (file EMU.ASM)
;**   (c) 2001-2004  tom ehlert
;**
;** The rest of the 32bit source is Public Domain.
;**
;*****************************************************************************
    TITLE JEMM - Virtual 8086-Monitor
    NAME JEMM

;--- to be assembled with JWasm or Masm v6.1+

    .486P
    .model FLAT
    option proc:private
    option dotname

    include jemm.inc        ;common declarations
    include jemm32.inc      ;declarations for Jemm32
    include debug.inc

;--- equates

;--- assembly time constants

?NMI        equ 1       ; std=1, 1=allow NMIs inside the monitor
?SKIPINT06  equ 1       ; std=1, 1=skip routing v86 exc to v86 int06


if ?INTEGRATED
?FREEXMS    equ 1       ; std=1, 0 might work
?NAME       equ <"JemmEx">
else
?FREEXMS    equ 1       ; std=1, 1=free all XMS on exit
?NAME       equ <"Jemm386">
endif

MAXBLOCKSIZE equ 40000h ; std=256 kB

;--- publics/externals

    include external.inc

;--- macros

@v86pushreg macro
    PUSHAD
    MOV EBP,ESP
    endm
@v86popreg macro
    POPAD
    endm
@v86popregX macro
    mov esp,ebp
    POPAD
    endm

;    assume SS:FLAT,DS:FLAT,ES:FLAT

.text$01 SEGMENT

;--- start: the binary's entry must be at offset 0!

    public _start

_start:
    jmp InitMonitor

;--- this is a 128 byte helper stack used for VCPI switches to
;--- protected-mode.

    db ?HLPSTKSIZE-5 dup (55h)

;--- IDT - Interrupt Descriptor Table
;--- as default, the IDT is no longer in the shared region

;--- global monitor data

V86CR3  DD 0                ; CR3 for monitor address context

IDT_PTR LABEL FWORD         ; size+base IDT
    DW 7FFH
if ?SHAREDIDT
    DD offset V86IDT
else
dwV86IDT DD 0
endif
wMasterPICBase  dw 0008h    ; put it here for alignment

GDT_PTR LABEL FWORD         ; size+base GDT
    DW GDT_SIZE-1
    DD offset V86GDT

wSlavePICBase   dw 0070h    ; put it here for alignment

dwFeatures      dd 0        ; features from CPUID 
dwStackCurr     dd ?TOS - ?STKSIZE
dwStackR0       dd 0        ; current R0 stack to compare
if ?DYNTRAPP60
dwTSS           dd 0
endif
dwTotalMemory   dd 0        ; XMS highest address (r/o)
bpstart         dd 0        ; linear address start of bp table
PageMapHeap     dd ?SYSLINEAR+?PAGETABSYS+6*4
pSmallHeap      label dword ; used during Init only
OldInt06        dd 0
dwHeapSize      label dword ; used during Init only
OldInt19        dd 0
OldInt67        dd 0
if ?SAFEKEYBOARD
OldInt16        dd 0        ; store to have a safe keyboard input
endif

    public  pSmallHeap
    public  dwHeapSize

dwRes           dd  0   ; linear address of resident segment
if ?HOOK13
dwRFlags        dd  0   ; linear address bRFlags
endif
dwRSeg          label dword
wRSeg           dw  0   ; resident segment
                dw  0
if ?FASTBOOT
pSavedVecs      dd 0    ;vectors saved during startup
;dwInt19Org     dd 0    ;original int 19 vector saved by DOS
endif

;-- byte vars (variable)

;-- byte vars (rather constant)

bNoPool         DB  0   ; flags pooling with XMS memory
bNoInvlPg       DB  -1  ; <> 0 -> dont use INVLPG
bV86Flags       DB  0   ; other flags 
bFatal          db  0   ; fatal exception, dont call DOS

bIs486          db  0   ; cpu is 486 or better (INVLPG opcode available)
if ?PGE
bPageMask       db  0   ;mask for PTEs in 0-110000h
endif
bBpTab          db  0   ;offset start bptable in RSEG
bBpBack         db  BPTABLE.pBack shr 2
ife ?HOOK13
bDiskIrq        db  0   ;diskette transfer pending
endif

    align 4

RunEmuInstr:
EmuInstr    DB  90h,90h,90h ; run self-modifying code here
            ret

;--- place rarely modified data here
;--- so data and code is separated by at least 64 "constant" bytes

if ?ROMRO
dwSavedRomPTE dd ?  ;saved PTE for FF000 page faults
dqSavedInt01  dq ?  ;saved INT 01
endif

.text$01 ends

if ?SHAREDGDT
.text$01x segment para public 'CODE'
else
.text$03x segment para public 'CODE'
endif

;--- GDT - Global Descriptor Table
;--- as default, the GDT is no longer in the shared region

V86GDT LABEL descriptor
    DQ 0                                ; +00 NULL-Entry
    descriptor <-1,0,0,9AH,0CFh,0>      ; +08 flat 4 GB Code (32 Bit)
    descriptor <-1,0,0,92H,0CFh,0>      ; +10 flat 4 GB Data (32 Bit)
    descriptor <?TSSLEN-1,0,0,89H,0,0>  ; +18 TSS V86
    descriptor <-1,0,0,9AH,0,0>         ; +20 std 64k Code Descriptor
    descriptor <-1,0,0,92H,0,0>         ; +28 std 64k Data Descriptor
    descriptor <?HLPSTKSIZE-1,0,?BASE shr 16,92H,040h,?BASE shr 24>; helper stack segment
    DQ 0                                ; +38
    descriptor <2FFh,400h,0,0F2H,0,0>   ; +40

    descriptor (GDT_SIZE - 9*8)/8 dup (<0,0,0,0,0,0>)

if ?SHAREDGDT
.text$01x ends
else
.text$03x ends
endif

if ?SHAREDIDT
    public V86IDT
.text$01x segment para public 'CODE'
V86IDT  DQ 100h dup (0)
.text$01x ends
endif

.text$03 segment

;--- v86 breakpoint table
;--- order must match the one defined in Jemm16.asm

bptable label BPTABLE
    dd Int06_V86Entry       ; BP06, default v86 int 06 handler
    dd Int19_V86Entry       ; BP19, Reboot
    dd Int67_V86Entry       ; BP67, default v86 int 67 handler
if ?VDS
    dd vds_handler          ; BPVDS, VDS handler, v86 int 4Bh
endif
    dd V86_Back             ; BPBACK, return to pm after calling v86-code
    dd I15_Simulate87       ; BP1587, simulate Int 15h, ah=87h
if ?HOOK13
    dd Dma_CopyBuffer       ; BP1340, INT13/40 DMA read op thru buffer
endif
    dd xms_handler          ; BPXMS, XMS handler (UMB+A20)
    dd EMMXXXX0_Strategy    ; BPSTRAT, EMMXXXX0 device strategy routine
    dd EMMXXXX0_Interrupt   ; BPDEV, EMMXXXX0 device interrupt routine
if ?UNLOAD
    dd Unload               ; BPUNL, unload Jemm, return to real-mode
endif

NUMBP equ (size BPTABLE)/4

;--- IO trapping table

IO_Trap_Table label dword
IO_Trap_Handler dd Default_IO_Trap_Handler
    dd (endportmap - portmap) / size IOTRAPENTRY
portmap label byte
if ?DMA
    IOTRAPENTRY <000h,00Fh,Dma_HandleDmaPorts8>
    IOTRAPENTRY <080h,08Fh,Dma_HandlePagePorts>
    IOTRAPENTRY <0C0h,0DFh,Dma_HandleDmaPorts16>
endif
if ?A20PORTS
    IOTRAPENTRY <060h,060h,A20_Handle60>
    IOTRAPENTRY <064h,064h,A20_Handle64>
    IOTRAPENTRY <092h,092h,A20_Handle92>
endif
endportmap label byte

    align 4

if ?ROMRO

PageFaultFF proc

    @DbgOutS <"Write access to FF000",10>, ?V86DBG
    @GETPTEPTR ebx, ?PAGETAB0+0FFh*4, 1
    mov ecx, [ebx]  ;get PTE for FF000
    mov dword ptr [ebx], 0FF000h + 111B ;set the "original" PTE
    mov [dwSavedRomPTE], ecx
    call @@invlpgFF

    mov ecx, offset @@pagefaultcont
    mov ax, FLAT_CODE_SEL
    shl eax, 16
    mov ax, cx
    mov cx, 0EE00h

if ?SHAREDIDT
    mov ebx, offset V86IDT
else
    mov ebx, dwV86IDT
endif
    xchg eax, [ebx+1*8+0]
    xchg ecx, [ebx+1*8+4]
    mov dword ptr [dqSavedInt01+0], eax
    mov dword ptr [dqSavedInt01+4], ecx
    or byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1, 1  ;TF=1
    @v86popregX             ; return to V86, execute 1 instruction
    ADD ESP,4+4
    iretd

;--- returned to monitor after 1 instruction run in v86 mode

@@pagefaultcont:
    pushad
    push ss
    pop ds
    @DbgOutS <"After write access to FF000",10>, ?V86DBG
    mov ecx, [dwSavedRomPTE]
    @GETPTEPTR eax, ?PAGETAB0+0FFh*4, 1
    mov [eax],ecx
    xor eax, eax
    mov cr2, eax
    mov eax, dword ptr [dqSavedInt01+0]
    mov ecx, dword ptr [dqSavedInt01+4]
if ?SHAREDIDT
    mov ebx, offset V86IDT
else
    mov ebx, dwV86IDT
endif
    mov [ebx+1*8+0], eax
    mov [ebx+1*8+4], ecx
    call @@invlpgFF
    popad
    and byte ptr [esp].IRETDV86.vEFL+1,not 1    ;TF=0
    iretd
@@invlpgFF:
if ?INVLPG
    cmp [bNoInvlPg],0
    jnz @@noinvlpg
    invlpg ds:[0FF000h]
    ret
@@noinvlpg:
endif
    mov eax, cr3
    mov cr3, eax
    ret
    align 4

PageFaultFF endp

endif

;--- print string at [ESP+4] with nested execution.

PrintString proc
    push esi
    push edi
if 0
    @DbgOutS <"PrintString",10>,1
    @WaitKey 1,0
endif
    sub esp,size Client_Reg_Struc
    mov edi, esp
    call Save_Client_State
    call Begin_Nest_Exec
    mov esi, [esp+size Client_Reg_Struc + 8 + 4]
@@nextchar:
    lodsb
    and al,al
    jz @@done
 if ?USEINT10
    mov ah,0Eh
    mov word ptr [EBP].Client_Reg_Struc.Client_EAX,ax
    mov word ptr [EBP].Client_Reg_Struc.Client_EBX,0007
    mov eax,10h
 else
    mov byte ptr [EBP].Client_Reg_Struc.Client_EAX,al
    mov eax,29h
 endif
    call Exec_Int
    jmp @@nextchar
@@done:
    call End_Nest_Exec
    mov esi, esp
    call Restore_Client_State
    add esp,size Client_Reg_Struc
    pop edi
    pop esi
    ret 4
    align 4

PrintString endp

;--- helper routines

dw2a proc            ; display DWORD in eax into EDI
    push eax
    shr eax,16
    call w2a
    pop eax
dw2a endp            ; fall through
w2a proc            ; display WORD in ax into EDI
    push eax
    mov al,ah
    call b2a
    pop eax
w2a endp            ; fall through
b2a proc            ; display BYTE in al into EDI
    push eax
    shr al,4
    call @@nibout
    pop eax     ; fall through
@@nibout:               ; display NIBBLE in al[0..3] into EDI
    and al,0Fh
    cmp al,10
    sbb al,69H
    das
    stosb
    ret
    align 4
b2a endp

?WSTARG equ 2

excitem struct
_bSize      db ?
bOfs        db ?
if ?WSTARG eq 2
dwTarget    dw ?
else
dwTarget    dd ?
endif
excitem ends

@excitem macro size_, src, dst
if ?WSTARG eq 2
    excitem {size_, src, LOWWORD(offset dst - offset exc_str)}
else
    excitem {size_, src, offset dst}
endif
    endm

;--- render register contents
;--- [ESP+4]: item descriptor
;--- may modify all general purpose registers except EBP

renderitems proc
    pop eax
    pop esi     ;get parameter
    push eax
@@nextitem:
    mov al, [esi].excitem._bSize
    cmp al, -1
    jz @@done_exc
    mov bl, al
    movsx eax, [esi].excitem.bOfs
if ?WSTARG
    movzx edi, [esi].excitem.dwTarget
    add edi, offset exc_str
else
    mov edi, [esi].excitem.dwTarget
endif
    add esi, size excitem
    MOV eax, ss:[ebp+eax]   ;use SS prefix here!
    push offset @@nextitem
    cmp bl,2
    jz b2a
    cmp bl,4
    jz w2a
    jmp dw2a
@@done_exc:
    ret
renderitems endp

.text$01w segment dword public 'CODE'

exc_str label byte
    DB 13,10, ?NAME, ": exception "
exc_no db 2 dup (' ')
    db " occured at CS:EIP="
exc_cs db 4 dup (' ')
    db ':'
exc_eip db 8 dup (' ')
    db ", ERRC="
exc_errc db 8 dup (' ')
    db 13,10
    db "SS:ESP="
exc_ss db 4 dup (' ')
    db ':'
exc_esp db 8 dup (' ')
    db " EBP="
exc_ebp db 8 dup (' ')
    db " EFL="
exc_efl db 8 dup (' ')
    DB " CR0="
exc_cr0 db 8 dup (' ')
    DB " CR2="
exc_cr2 db 8 dup (' ')
    db 13,10
    db "EAX="
exc_eax db 8 dup (' ')
    db " EBX="
exc_ebx db 8 dup (' ')
    db " ECX="
exc_ecx db 8 dup (' ')
    db " EDX="
exc_edx db 8 dup (' ')
    db " ESI="
exc_esi db 8 dup (' ')
    db " EDI="
exc_edi db 8 dup (' ')
    db 13,10
    db 0

exc_str2 label byte
    db "DS="
exc_ds db 4 dup (' ')
    db " ES="
exc_es db 4 dup (' ')
    db " FS="
exc_fs db 4 dup (' ')
    db " GS="
exc_gs db 4 dup (' ')
    db ' [CS:IP]='
exc_csip db 8*3 dup (' ')
    db CR,LF,'Press ESC to abort program ', 0
    db 0

exc_str3 db 13, ?NAME, ': unable to continue. Please reboot '
    db 0
szCRLF db CR,LF
    db 0

exc_format label excitem
    @excitem 2, Client_Reg_Struc.Client_Int   , exc_no
    @excitem 4, Client_Reg_Struc.Client_CS    , exc_cs
    @excitem 8, Client_Reg_Struc.Client_EIP   , exc_eip
    @excitem 8, Client_Reg_Struc.Client_Error , exc_errc
    @excitem 4, -4                            , exc_ss
    @excitem 8, -8                            , exc_esp
    @excitem 8, Client_Reg_Struc.Client_EBP   , exc_ebp
    @excitem 8, Client_Reg_Struc.Client_EFlags, exc_efl
    @excitem 8, -12                           , exc_cr0
    @excitem 8, -16                           , exc_cr2
    @excitem 8, Client_Reg_Struc.Client_EAX   , exc_eax
    @excitem 8, Client_Reg_Struc.Client_EBX   , exc_ebx
    @excitem 8, Client_Reg_Struc.Client_ECX   , exc_ecx
    @excitem 8, Client_Reg_Struc.Client_EDX   , exc_edx
    @excitem 8, Client_Reg_Struc.Client_ESI   , exc_esi
    @excitem 8, Client_Reg_Struc.Client_EDI   , exc_edi
    db -1

exc_v86segregs label excitem
    @excitem 4, Client_Reg_Struc.Client_DS    , exc_ds
    @excitem 4, Client_Reg_Struc.Client_ES    , exc_es
    @excitem 4, Client_Reg_Struc.Client_FS    , exc_fs
    @excitem 4, Client_Reg_Struc.Client_GS    , exc_gs
    db -1

    align 4

.text$01w ends

;--- the monitor entry
;--- it should not be at the very beginning of this segment

if ?FASTMON

@FASTMON macro x
    push x
    jmp short @@v86_monitor
    endm

    align 4

int00 label near
    INTNO = 0
    REPT ?FASTENTRIES
        @FASTMON INTNO
        INTNO = INTNO+1
    ENDM
endif

    align 4
    
@@v86_monitor:

; all entries in the IDT (except 15h and 67h) jump to V86_Monitor.
; It has to check if an exception has occured. If no, just reflect the 
; interrupt to v86-mode. If yes, check what the reason for the exception
; was and do the appropriate actions.
;
; inp: the cpu has set DS,ES,FS,GS==NULL if switch from v86 mode!
;  [ESP+0] = INT#

V86_Monitor PROC public

    @v86pushreg

    @DbgOutS <".">,?V86DBG

;-- we don't know for sure what size the stack is.
;-- There might exist other ring0 code which intruded in the
;-- monitors address context and modified GDT/IDT entries
;-- But at least they should have established a 32-bit stack or
;-- at the very least cleared HiWord(ESP) so EBP will point to a
;-- valid frame.

    MOVZX ECX,byte ptr [EBP].V86FRAME.fIntNo  ;load 1 byte ONLY!

; Three cases are considered:
; - INT executed in V86 mode     EBP = ?TOS - size V86FRAME
; - exception in V86 mode        EBP = ?TOS - size Client_Reg_Struc
; - EXC/IRQ (HLT) in v86 monitor EBP < ?TOS - size Client_Reg_Struc

    CMP EBP, ?TOS - size Client_Reg_Struc   ; exception in v86 mode?
    JZ V86_Exception
    CMP EBP, ?TOS - size V86FRAME           ; int/irq in v86 mode?
    JNZ @@IRQOREXC

if ?V86DBG
    @DbgOutS <"Int in v86-mode, #=">,1
    @DbgOutW cx,1
    @DbgOutS <", CS:EIP=">,1
    @DbgOutW <word ptr [ebp].V86FRAME.fCS>,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].V86FRAME.fEIP,1
    @DbgOutS <" EBP=">,1
    @DbgOutD ebp,1
    @DbgOutS <10>,1
endif

;--- simulate an int in v86 mode

    MOV ESI,[EBP].V86FRAME.fEIP
    MOV EDI,[EBP].V86FRAME.fCS
    MOV EDX,[EBP].V86FRAME.fEFL
    MOV EAX,[EBP].V86FRAME.fESP
    shl ecx,2
    MOVZX EBX, word ptr [EBP].V86FRAME.fSS
    SUB AX, 6                   ; Create space for IRET frame
    SHL EBX,4
    MOV [EBP].V86FRAME.fESP,EAX
    MOVZX EAX,AX                  ; use LOWORD(ESP) only!
    ADD EBX,EAX

; copy Interrupt frame down. Use SS, since DS is unset

    MOV SS:[EBX+0],SI
    MOV SS:[EBX+2],DI
    MOV SS:[EBX+4],DX
    MOV EAX,SS:[ECX]            ; route call to vector in real-mode IVT
    AND DH, NOT (1 or 2)        ; Clear IF+TF as it is done in real-mode
    MOV word ptr [EBP].V86FRAME.fEIP,AX
    SHR EAX, 16
    MOV [EBP].V86FRAME.fCS, EAX
    MOV [EBP].V86FRAME.fEFL, EDX

    @v86popreg
    add ESP,4           ; skip int#
    IRETD                   ; return to v86-mode

    align 4

;-- IRQ, NMI or exception in ring 0
;-- an exception may be with or without error code
;-- an allowed IRQ will have a known ESP and FLAT_CODE_SEL as CS

@@IRQOREXC:

if ?V86DBG
    @DbgOutS <"V86 IRQ/EXC, #=">,1
    @DbgOutW cx,1
    @DbgOutS <" EBP=">,1
    @DbgOutD ebp,1
    @DbgOutS <", CS:EIP=">,1
    @DbgOutW <word ptr [ebp].V86FRAME.fCS>,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].V86FRAME.fEIP,1
    @DbgOutS <" EFL=">,1
    @DbgOutD [ebp].V86FRAME.fEFL,1
    @DbgOutS <", SS:ESP=">,1
    @DbgOutW <word ptr [ebp].V86FRAME.fSS>,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].V86FRAME.fESP,1
    @DbgOutS <10>,1
    @WaitKey 1,1
endif
if ?NMI
    cmp ecx,2       ;NMI?
    JZ @@isnmi
endif
    cmp word ptr [ebp].V86FRAME.fCS,FLAT_CODE_SEL
    JNZ ring0_exc

;--- IRQs in ring 0 will only occur "controlled".
;--- This simplifies identifying them (Jemm doesn't reprogram the PICs!)

    lea eax,[esp + 8*4 + 3*4 + 4]   ;PUSHAD + IRET32 + INT#
    cmp eax,[dwStackR0]             ;is ESP that of an IRQ?
    jnz ring0_exc
@@isnmi:
    mov ebp, ?TOS - size Client_Reg_Struc
    push ecx
    call Begin_Nest_Exec
    pop eax
    call Exec_Int
    call End_Nest_Exec
    @v86popreg
    add ESP,4           ; skip int#
    IRETD
    align 4

V86_Monitor     ENDP

;--- breakpoint: handle exc 06 in v86-mode

Int06_V86Entry proc
    call Simulate_Iret
    mov [ebp].Client_Reg_Struc.Client_Int,6
Int06_V86EntryX::
    mov esp,ebp
    @v86popreg
    jmp errorcode_pushed
Int06_V86Entry endp

;--- handle exceptions (ring 0 protected-mode and v86-mode)
;--- display current register set
;--- if it is caused by external protected-mode code, display REBOOT option
;--- else jump to v86-mode and try to abort current PSP

;--- handle exceptions in ring0 protected-mode

ring0_exc proc
ring0_exc endp

HandleException proc
    mov eax, ss                 ; the stack size is not known
    lar eax, eax
    test eax,400000h
    jnz @@is32
    movzx esp,sp                  ; make sure ESP is valid
@@is32:
    @v86popreg

    cmp dword ptr [esp],8       ; exc #8?
    jnc errorcode_pushed
    push dword ptr [esp]         ; emulate error code for exc 0-7 
;    mov dword ptr [esp+4],0
errorcode_pushed::
    @v86pushreg

    mov ax, FLAT_DATA_SEL
    mov ds, eax
    mov ES, eax
    cld

if ?EXCDBG
    @DbgOutS <"Exception dump, exception ">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_Int,1
    @DbgOutS <" at cs:eip=">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_CS,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_EIP,1
    @DbgOutS <10>,1
endif

    test byte ptr [ebp].Client_Reg_Struc.Client_EFlags+2,2   ;V86 mode?
    jnz @@isv86
    mov byte ptr [exc_ds],' '   ;used as flag (see below)
    lar eax, [ebp].Client_Reg_Struc.Client_CS
    and ah,60h
    jnz @@isring3
    mov ebx, ss
    lea ecx,[ebp + Client_Reg_Struc.Client_ESP] ;is this correct?
    jmp @@isring0
@@isv86:

;--- exception in V86 mode: display next 8 bytes of [cs:eip]

    movzx esi,word ptr [ebp].Client_Reg_Struc.Client_CS
    shl esi,4
    add esi,[ebp].Client_Reg_Struc.Client_EIP
    mov cl,8
    mov edi,offset exc_csip
@@nextitem:
    lods byte ptr [esi]
    call b2a
    inc edi
    dec cl
    jnz @@nextitem
    
    push offset exc_v86segregs   ;render V86 segment registers
    call renderitems
@@isring3:
    mov ebx,dword ptr [ebp].Client_Reg_Struc.Client_SS
    MOV ecx,dword ptr [ebp].Client_Reg_Struc.Client_ESP
@@isring0:
    push ebx                     ; ebp-4 == SS
    push ecx                     ; ebp-8 == ESP
    mov eax, cr0
    push eax                     ; ebp-12
    mov eax, cr2
    push eax                     ; ebp-16

    push offset exc_format
    call renderitems

    mov esp,ebp

    mov eax,ss
    cmp ax, FLAT_DATA_SEL
    jnz @@external_exc
if 0
    cmp [ebp].Client_Reg_Struc.Client_Int, 0Ch  ;stack exception?
    jz @@external_exc
endif
    jmp @@printexcstr
@@external_exc:
    mov [bFatal],1
@@printexcstr:
    @v86popreg
    push ds
    pop ss
    mov esp, ?TOS - size Client_Reg_Struc + 8*4
    @v86pushreg

;--- reinit ring 0 stack

    mov esp,?TOS - ?STKSIZE
    mov [dwStackCurr],esp

;--- reset client's AC flag
;--- since we use v86-mode for displays now

    and byte ptr [ebp].Client_Reg_Struc.Client_EFlags+2,not 4
    
;--- make sure the first 4 entries in the breakpoint table are valid
;--- this will make Jemm work even if severe damage has been done to 
;--- the v86 memory.

    mov ecx, [bpstart]
    mov dword ptr [ecx], (?BPOPC shl 24) or (?BPOPC shl 16) or (?BPOPC shl 8) or ?BPOPC

    push offset exc_str
    call PrintString         ;this will call v86-mode

    cmp byte ptr [exc_ds],' '   ;segments rendered? (v86 mode exc?)
    jz @@nov86
    push offset exc_str2
    call PrintString
@@nov86:
    call Begin_Nest_Exec
@@waitkey:
    mov byte ptr [ebp].Client_Reg_Struc.Client_EAX+1, 00
    mov byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1, 30h    ;IOPL=3 (to be safe)
if ?SAFEKEYBOARD    
    mov eax,[OldInt16]
    xchg eax,ds:[16h*4]  ;make sure we have a safe keyboard
    push eax
endif
    mov eax,16h
    call Exec_Int
if ?SAFEKEYBOARD
    pop dword ptr ds:[16h*4]
endif
    cmp byte ptr [ebp].Client_Reg_Struc.Client_EAX, 1Bh
    jnz @@waitkey
    push offset szCRLF       ;print a CR/LF
    call PrintString
    cmp [bFatal],1
    jz @@nodoscall
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 4C7Fh
    mov eax,21h
    call Exec_Int
;--- if v86 returned (or exception is fatal), there is nothing to do than wait
@@nodoscall:
    or [bFatal],1
    push offset exc_str3 
    call PrintString
    jmp @@waitkey
    align 4

HandleException endp

;--- exception in V86 mode
;--- EBP->Client_Reg_Struc
;--- CX=int#

V86_Exception proc

if ?V86DBG  ;this happens quite often, so usually not good to activate
    @DbgOutS <"exception in v86-mode, #=">,1
    @DbgOutW cx,1
    @DbgOutS <", CS:IP=">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_CS>,1
    @DbgOutS <":">,1
    @DbgOutW <word ptr [ebp].Client_Reg_Struc.Client_EIP>,1
    @DbgOutS <10>,1
endif
    MOV EAX,SS
    MOV DS,EAX

    mov esp,[dwStackCurr]

if 0
    @DbgOutS <"V86_Exception, esp=">,1
    @DbgOutD esp,1
    @DbgOutS <" cs:eip=">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_CS,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_EIP,1
    @DbgOutS <10>,1
    @WaitKey 1,1
endif

    CMP ECX,0DH             ; general protection exception?
    JNZ @@V86_TEST_EXC      ; no, check further
@@Is_BP:
    MOV ES,EAX
    MOVZX ESI,word ptr [EBP].Client_Reg_Struc.Client_CS
    mov ecx,[EBP].Client_Reg_Struc.Client_EIP
    SHL ESI,4
    ADD ESI,ECX             ; ESI = linear CS:EIP

; check what triggered the GPF. Possible reasons are:

; - HLT opcode, which then might be:
;   + a "Breakpoint" if CS:EIP points into the breakpoint table.
;     call the breakpoint handler proc then.
;   + other HLTs. Is handled by running HLT in ring 0 inside the monitor.
; - trapped I/O command. I/O only causes GPF for masked ports.
;   The DMA, KBC and P92 ports are trapped inside Jemm, but external
;   modules may take over the whole IO port trapping (JLOAD).
; - other privileged opcode. Some are emulated (mov CRx, reg ...),
;   some are not and then are just translated to an int 6, illegal opcode,
;   which is then reflected to the V86 task!).
;
    MOV AL,[ESI]                ; check opcode
    cmp AL, ?BPOPC
    jnz @@NoBPOPC               ; breakpoint?
    mov eax, [bpstart]
    sub esi, eax
    jb @@No_BP
    cmp esi, NUMBP
    jae @@No_BP
    call [offset bptable + esi*4]
    mov esp,ebp
    @v86popreg
    add ESP,4+4         ; skip int# + error code
    IRETD

if ?BPOPC ne 0F4h
    align 4
Int06_Entry::
    push 0       ;exc 06 has no error code, set a dummy one
    push 6
    @v86pushreg
    mov eax, ss
    mov ds, eax
    jmp @@Is_BP
endif

@@No_BP:
if ?BPOPC ne 0F4h
    jmp V86_Exc0D
endif
@@Is_Hlt:

if ?HLTDBG
    @DbgOutS <"True HLT occured at CS:IP=">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_CS,1
    @DbgOutS <":">,1
    @DbgOutD [ebp].Client_Reg_Struc.Client_EIP,1
    @DbgOutS <10>,1
endif

    INC [EBP].Client_Reg_Struc.Client_EIP   ; Jump over the HLT instruction
    @v86popregX

    mov esp,[dwStackCurr]    
;   ADD ESP,4+4             ; throw away errorcode & INT#

if 0
;--- doing a HLT with interrupts disabled will freeze the machine
;--- (or at least wait for a NMI). MS Emm386 does so. Should Jemm as well?
    test byte ptr [ESP].IRETDV86.vEFL+2,2
    jz @@run_hlt
endif
    call EnableInts
    STI                         ; give Interrupts free and then wait
    HLT
    CLI
    call DisableInts
    mov esp,?TOS - size IRETDV86
    iretd                       ; will it ever hit this?

@@NoBPOPC:

if ?BPOPC ne 0F4h
    CMP     AL,0F4H                 ; HLT-
    JZ      @@Is_Hlt                ; command ?
endif

if ?SB
; see if SoundBlaster INT 3 forced to 1ah error code GPF

    CMP [EBP].Client_Reg_Struc.Client_Error,1ah
    jne @@notsb
    test [bV86Flags],V86F_SB
    je @@notsb                 ; SB option not turned on
    inc [EBP].Client_Reg_Struc.Client_EIP   ; skip INT 3 opcode
    @v86popregX
    add esp,4+4                 ; discard excess GPF error code
    push 3                      ; simulate an INT 3
    jmp V86_Monitor
@@notsb:
endif

if ?EMUDBG
    @DbgOutS <"Opcode ">,1
    @DbgOutB AL,1
    mov ah, [esi+1]
    @DbgOutS <" ">,1
    @DbgOutB AH,1
    mov ah, [esi+2]
    @DbgOutS <" ">,1
    @DbgOutB AH,1
    @DbgOutS <" caused GPF at ">,1
    @DbgOutD esi,1
    @DbgOutS <10>,1
endif

    cmp al,0Fh                  ; check if potentially mov <reg>,cr#
    je ExtendedOp
    mov cl,0
    mov edi, esi
    cmp al,0F3h
    setz ch
    jnz @@norepprefix
    inc esi
    mov al,[esi]
@@norepprefix:
    cmp al,66h
    setz ah
    jnz @@nosizeprefix
    inc esi
    mov al,[esi]
@@nosizeprefix:
    cmp al,6Ch
    JB V86_Exc0D
    cmp al,6Fh                  ; string IO ?
    JBE @@DoIO_String
    CMP AL,0E4H
    JB V86_Exc0D
    CMP AL,0E7H                 ; IN/OUT xx ?
    JBE @@DoIO_Im
    CMP AL,0ECH
    JB V86_Exc0D
    CMP AL,0EFH                 ; IN/OUT DX ?
    JBE @@DoIO_DX
    JMP V86_Exc0D

;--- exception (not 0Dh) in V86 mode
;--- DS=FLAT, ECX=INT#

@@V86_TEST_EXC:

if ?ROMRO
    cmp ECX, 0Eh
    jnz @@V86_EXC_NOT0D0E
    mov eax, CR2
    shr eax, 12
    cmp eax, 0FFh      ;it is the FF000 page (which is r/o!)
    jz PageFaultFF

;--- unhandled v86-mode exception 0Eh occured 

@@V86_EXC0E:

endif

;*************************************************************
; unhandled exception in v86-mode. simulate a v86 exception 06.
; this notifies any hookers about the problem. If noone has hooked
; v86-int 06, we finally end at the monitor again, display a register
; dump and then try to terminate the current PSP.
;*************************************************************

;--- unhandled v86-mode exception xxh occured

@@V86_EXC_NOT0D0E:

;--- unhandled v86-mode exception 0Dh occured

if ?V86EXC0D
	jmp noexcrtn
endif
V86_Exc0D::

if ?V86EXC0D

;--- V86EXC0D option set? If yes, route the exception to
;--- v86 int 0Dh instead of int 06h.

    test [bV86Flags], V86F_V86EXC0D
    mov eax,0Dh
    jnz v86excrtn
noexcrtn:
endif

;--- if "noone" has hooked v86 int 06 vector, there's
;--- no need to route v86 exceptions to v86-mode, since
;--- it just will be thrown back to Jemm. This allows to
;--- display the true exception number (0C/0D/0E/..)

if ?SKIPINT06
    movzx eax,word ptr ds:[6*4+2]
    cmp eax,[dwRSeg]
    jz Int06_V86EntryX
endif

;--- simulate invalid opcode interrupt in v86 mode

    mov eax,6
v86excrtn:
    call [vmm_service_table.pSimulate_Int]
    @v86popregX
    add ESP,4+4         ; remove error code + old calling address
    IRETD                   ; return to virtual 86-Mode

    align 4

;***************************************

; IO command has been trapped

;--- opcode E4-E7 (IN AL,XX ; IN AX,XX ; OUT XX, AL ; OUT XX, AX)

@@DoIO_String:  ;<- entry for opcode 6C-6F
    rol ecx,16
    mov cx,word ptr [ebp].Client_Reg_Struc.Client_ES
    test al,2
    jz @@isstrin
    mov cx,word ptr [ebp].Client_Reg_Struc.Client_DS
@@isstrin:
    rol ecx,16
    or cl,STRING_IO
    shl ch,6
    or cl,ch   ;set REP bit
    JMP @@DoIO_DX

@@DoIO_Im:
    INC ESI
    MOVZX EDX,BYTE PTR [ESI]              ; get I/O port in DX
@@DoIO_DX:      ;<- entry for opcode EC-EF, expects DX = Client_DX
    inc esi
    and ah,al   ;if AH still 1, it is DWORD IO
    shl ah,4
    or cl,ah
    shr ah,4
    xor ah,al
    and ah,1
    shl ah,3
    or cl,ah
    and al,2
    shl al,1
    or cl,al

    sub esi, edi
    add [ebp].Client_Reg_Struc.Client_EIP, esi
    mov eax, [ebp].Client_Reg_Struc.Client_EAX

;--- now DX, EAX and CL is set for the IO handlers    

    push ecx
    call [IO_Trap_Handler]
    pop ecx
    test cl,OUTPUT or STRING_IO
    jnz @@isout
    mov [ebp].Client_Reg_Struc.Client_EAX, eax
@@isout:
    @v86popregX
    ADD ESP,4+4
    IRETD

    align 4

V86_Exception endp

Default_IO_Trap_Handler proc

if 1    ;all internal functions handle byte i/o only
    test cl,STRING_IO or DWORD_IO or WORD_IO
    jnz Simulate_IO
endif
    mov esi, offset portmap
@@nextport:
    cmp dl, [esi].IOTRAPENTRY.bStart
    jb @@skipport
    cmp dl, [esi].IOTRAPENTRY.bEnd
    jbe @@portfound
@@skipport:
    add esi,size IOTRAPENTRY
    cmp esi, offset endportmap
    jnz @@nextport
    jmp Simulate_IO
@@portfound:
    jmp dword ptr [esi].IOTRAPENTRY.dwProc
    align 4

Default_IO_Trap_Handler endp

;--- Simulate_IO, expects:
;--- EBP -> client ptr
;--- CX = flags
;--- Hiword(ECX) = segment of src/dst for string IO
;--- EAX = data (if OUTPUT flag is set)
;--- DX = port

;--- it converts:
;--- WORD IO -> BYTE IO
;--- DWORD IO -> WORD IO
;--- STRING IO -> DWORD/WORD/BYTE IO
;--- REP STRING IO -> multiple DWORD/WORD/BYTE IO

Simulate_IO proc public

    test cl,STRING_IO
    jnz @@isstrio
    movzx ebx,cl
    and ebx,1Ch
    jmp [ebx + offset iojmp]
    align 4

iojmp label dword
    dd @@bin
    dd @@bout
    dd @@win
    dd @@wout
    dd @@din
    dd @@dout

@@bin:
    in al,dx
    ret
@@bout:
    out dx,al
    ret
@@win:
    and cl,not WORD_IO
    push edx
    push ecx
    call [IO_Trap_Handler] 
    pop ecx
    mov edx,[esp]
    inc edx
    push eax    
    call [IO_Trap_Handler]
    mov [esp+1],al
    pop eax
    pop edx
    ret
@@wout:
    and cl,not WORD_IO
    push edx
    push ecx
    call [IO_Trap_Handler] 
    pop ecx
    mov edx,[esp]
    inc edx
    mov al,ah
    call [IO_Trap_Handler]
    pop edx
    ret
@@din:
    and cl,not DWORD_IO
    or cl,WORD_IO
    push edx
    push ecx
    call [IO_Trap_Handler] 
    pop ecx
    mov edx,[esp]
    add edx,2
    push eax
    call [IO_Trap_Handler]
    mov [esp+2],ax
    pop eax
    pop edx
    ret
@@dout:
    and cl,not DWORD_IO
    or cl,WORD_IO
    push edx
    push ecx
    call [IO_Trap_Handler] 
    pop ecx
    pop edx
    add edx,2
    shr eax,16
    jmp [IO_Trap_Handler]

@@isstrio:
    test cl, REP_IO
    jz @@isnorepio
    and cl, not REP_IO
    jmp @@teststr
@@nextio:
    push ecx
    push edx
    call @@isnorepio
    pop edx
    pop ecx
    dec word ptr [ebp].Client_Reg_Struc.Client_ECX
@@teststr:
    cmp word ptr [ebp].Client_Reg_Struc.Client_ECX,0
    jnz @@nextio
    ret

@@isnorepio:
    and cl,not STRING_IO
    movzx ebx,cl
    and ebx,1Ch
    jmp [ebx + offset siojmp]
    align 4

siojmp label dword
    dd @@sbin
    dd @@sbout
    dd @@swin
    dd @@swout
    dd @@sdin
    dd @@sdout

@@sbin:
    call @@sxin
    stosb
    add word ptr [ebp].Client_Reg_Struc.Client_EDI,1
    ret
@@swin:
    call @@sxin
    stosw
    add word ptr [ebp].Client_Reg_Struc.Client_EDI,2
    ret
@@sdin:
    call @@sxin
    stosd
    add word ptr [ebp].Client_Reg_Struc.Client_EDI,4
    ret
@@sxin:
    call [IO_Trap_Handler]
    rol ecx, 16
    movzx esi,cx
    rol ecx, 16
    shl esi, 4
    movzx edi, word ptr [ebp].Client_Reg_Struc.Client_EDI
    add edi, esi
    ret

@@sbout:
    call @@sxout
    lodsb
    add word ptr [ebp].Client_Reg_Struc.Client_ESI,1
    jmp [IO_Trap_Handler]
@@swout:
    call @@sxout
    lodsw
    add word ptr [ebp].Client_Reg_Struc.Client_ESI,2
    jmp [IO_Trap_Handler]
@@sdout:
    call @@sxout
    lodsd
    add word ptr [ebp].Client_Reg_Struc.Client_ESI,4
    jmp [IO_Trap_Handler]
@@sxout:
    rol ecx, 16
    movzx eax,cx
    rol ecx, 16
    shl eax, 4
    movzx esi, word ptr [ebp].Client_Reg_Struc.Client_ESI
    add esi, eax
    ret

    align 4

Simulate_IO endp

if ?EXC10

;--- detect exception 10h. This exception has NO error code.
;--- With VME enabled, it would be no problem, but since the VME bit
;--- in CR4 can be cleared by the user or other programs, Jemm cannot
;--- rely on that. So it checks:
;--- 1. if NE is set. No -> Int 10h
;--- 2. if ([CS:IP] != 9B) && ([CS:IP] != D8..DF) -> Int 10h
;--- 3. check for FP status word bit 7 set:
;---   (a. coprocessor available (00000410, bit 1=1))
;---   b. FNSTSW AX, check bit 1, if 0 -> Int 10h
;---
;--- Else it is an exception, and a dummy error code of 0 is pushed,
;--- which will make V86_Monitor recognize it as such.
;---
;--- Jemm doesn't clear the FP status word by a FNINIT, so any FP instruction
;--- will continue to cause an exception 10h unless it is cleared.
;--- If the NE bit in CR0 isn't set, an IRQ 13 (interrupt 75h) is launched
;--- instead of exception 10h.

Int10_Entry proc public
    push eax
    mov eax,cr0
    test al,20h     ;NE bit set? (usually it is 0)
    jnz maybeexc10
isint10:
    pop eax
    push 10h
    jmp V86_Monitor
maybeexc10:
    movzx eax, word ptr [esp+4].IRETDV86.vCS
    shl eax, 4
    add eax, [esp+4].IRETDV86.vEIP
    mov al,cs:[eax]
    cmp al,9Bh      ;WAIT?
    jz @F
    and al,0F8h     ;or a FPU opcode?
    cmp al,0D8h
    jnz isint10     ;no, then it's an Int 10h
@@:
    fnstsw ax
    test al,80h     ;a FPU error pending?
    jz isint10      ;if no, then it's an Int 10h
    pop eax
    push 0          ;push a 0 as error code 
    push 10h
    jmp V86_Monitor
    align 4
Int10_Entry endp

endif

;--- copy physical memory
;--- esi=src, edi=dst, ecx=size
;--- addresses > 10FFFFh are regarded as physical addresses
;--- used by XMS block moves and Int 15h, ah=87h
;--- modifies eax, ebx, ecx, edx, esi, edi

;?MEMBORDER equ 110000h
?MEMBORDER equ 100000h

MoveMemoryPhys proc public

    mov eax, ecx
@@extmove_loop:
    mov ecx, eax
    cmp ecx, MAXBLOCKSIZE
    jb @F
    mov ecx, MAXBLOCKSIZE
@@:
    sub eax, ecx
    push eax
    push esi
    push edi
    push ecx

    mov edx,[PageMapHeap]
    push edx

    push ecx

;--- get no of PTEs involved (max is 16+1)

    add ecx,1000h-1 ;round up size to page boundary
    shr ecx,12      ;bytes -> PTEs (10000h -> 10h)
    inc ecx         ;add 1 to account for base not aligned on page boundary
    mov ch, cl

    cmp esi, ?MEMBORDER   ;src in real-mode address space?
    jc  @@src_is_shared
    mov eax, esi
    and esi, 0FFFh
    call MapPhysPages
if ?PHYSDBG
    @DbgOutS <"MoveMemoryPhys: ">, 1
    @DbgOutB ch, 1
    @DbgOutS <" pages (src) mapped at ">, 1
    @DbgOutD eax, 1
    @DbgOutS <10>, 1
endif
    add esi, eax
    mov cl, ch
@@src_is_shared:
    cmp edi, ?MEMBORDER
    jc  @@dst_is_shared
    mov eax, edi
    and edi, 0FFFh
    call MapPhysPages
if ?PHYSDBG
    @DbgOutS <"MoveMemoryPhys: ">, 1
    @DbgOutB ch, 1
    @DbgOutS <" pages (dst) mapped at ">, 1
    @DbgOutD eax, 1
    @DbgOutS <10>, 1
endif
    add edi, eax
@@dst_is_shared:
if ?INVLPG
    cmp [bNoInvlPg],0
    jz @@flushdone
endif
    mov eax, cr3
    mov cr3, eax
@@flushdone:
    pop ecx
    mov [PageMapHeap], edx  ;update in case the monitor is reentered
    call MoveMemory
    pop [PageMapHeap]
    pop ecx
    pop edi
    pop esi
    pop eax
    add edi,ecx
    add esi,ecx
    and eax, eax
    jnz @@extmove_loop
    ret
    align 4

MoveMemoryPhys endp

?WT equ 0       ; std=0, 1=set WT bit in PTE for mem moves

if ?WT
?PA equ 1+2+4+8 ;PRESENT + R/W + USER + WRITE THROUGH
else
?PA equ 1+2+4   ;PRESENT + R/W + USER
endif

;--- map physical pages in page map heap

MapPhysPagesEx proc public
    mov edx, [PageMapHeap]
MapPhysPagesEx endp     ;fall thru

;--- map physical pages in linear address space
;--- in:  eax = start of physical region to map
;---      edx -> free entry in page map heap
;---      cl = no of 4kB pages to map
;--- out: eax = linear address where the region has been mapped
;---      edx -> next free entry in page map heap
;--- modifies ebx, cl

MapPhysPages proc public

    mov ebx, edx
    sub ebx, ?SYSLINEAR+?PAGETABSYS
    shl ebx, 10
    add ebx, ?SYSBASE
    and ah, 0F0h
    mov al,?PA
if ?INVLPG    
    cmp [bNoInvlPg],0
    jz @@setPTEs486
endif

@@nextPTE1:
    mov [edx], eax
    add eax, 1000h
    add edx,4
    dec cl
    jnz  @@nextPTE1
    mov eax, ebx
    ret
    align 4

if ?INVLPG
@@setPTEs486:
    push ebx
@@nextPTE2:
    mov [edx], eax
    invlpg ds:[ebx]
    add edx,4
    add eax, 1000h
    add ebx, 1000h
    dec cl
    jnz  @@nextPTE2
    pop eax
    ret
endif
    align 4

MapPhysPages endp

;--- copy memory block ESI to EDI, size ECX
;--- allow interrupts during move op

MoveMemory proc public
    mov eax, [ebp].Client_Reg_Struc.Client_EFlags
    test ah,2
    jz @@noenable
    call EnableInts
    sti
@@noenable:

    mov al,cl
    shr ecx,2
    and al,3
    REP MOVSD
    mov cl,al
    REP MOVSB

    test ah,2
    jz @@nodisable
    cli
    call DisableInts
@@nodisable:
    ret
    align 4

MoveMemory endp

;--- allow interrupts in the monitor

EnableInts proc public
    push [dwStackR0]
    mov [dwStackR0],esp
    jmp dword ptr [esp+4]
    align 4
EnableInts endp

DisableInts proc public
    pop [esp+4]
    pop [dwStackR0]
    ret
    align 4
DisableInts endp

Yield proc public
    test byte ptr [ebp].Client_Reg_Struc.Client_EFlags+1,2
    jz @@noints
    call EnableInts
    sti
    nop            ;interrupts are enabled 1 instruction *after* STI
    cli
    call DisableInts
@@noints:
    ret
    align 4
Yield endp

;--- simulate an RETF in v86-mode
;--- INP: EBP -> client struct
;--- modifies EAX,ECX

Simulate_Far_Ret proc public
    MOVZX eax, word ptr [EBP].Client_Reg_Struc.Client_ESP
    MOVZX ecx, word ptr [EBP].Client_Reg_Struc.Client_SS
    SHL ecx, 4
    add ecx, eax
    MOV eax, [ecx+0]
    mov word ptr [EBP].Client_Reg_Struc.Client_EIP, ax
    shr eax,16
    mov [EBP].Client_Reg_Struc.Client_CS, eax
    ADD [EBP].Client_Reg_Struc.Client_ESP,2*2
    ret
    align 4
Simulate_Far_Ret endp

;--- simulate a far call in v86-mode
;--- EBP -> client struct
;--- cx: new CS
;--- edx: new EIP (hiword ignored)

Simulate_Far_Call proc public
    xchg edx, [EBP].Client_Reg_Struc.Client_EIP
    xchg cx, word ptr [EBP].Client_Reg_Struc.Client_CS
    push ecx
    MOVZX ecx, word ptr [EBP].Client_Reg_Struc.Client_SS
    MOVZX eax, word ptr [EBP].Client_Reg_Struc.Client_ESP
    sub ax, 4
    mov word ptr [EBP].Client_Reg_Struc.Client_ESP, ax
    shl ecx, 4
    add eax, ecx
    mov [eax+0],dx
    pop ecx
    mov [eax+2],cx
    ret
    align 4
Simulate_Far_Call endp

;--- prepare for nested execution. Push the "back" bp onto the client's stack

Begin_Nest_Exec proc public
    mov ecx,[dwRSeg]
    movzx edx, [bBpBack]
    jmp Simulate_Far_Call
    align 4

Begin_Nest_Exec endp

;--- simulate an IRET in v86-mode
;--- INP: EBP -> Client_Reg_Struc
;--- modifies EAX,ECX,EDX

Simulate_Iret proc public
    MOVZX eax, word ptr [EBP].Client_Reg_Struc.Client_ESP
    MOVZX ecx, word ptr [EBP].Client_Reg_Struc.Client_SS
    SHL ecx, 4
    add eax, ecx
    MOV edx, [eax+0]
    MOV cx, [eax+4]
    mov word ptr [EBP].Client_Reg_Struc.Client_EIP,dx
    shr edx,16
    mov [EBP].Client_Reg_Struc.Client_CS, edx
if 1
    or ch,30h   ;to be safe, set IOPL=3 for v86
endif
    mov word ptr [EBP].Client_Reg_Struc.Client_EFlags,cx
    ADD [EBP].Client_Reg_Struc.Client_ESP,3*2
    ret
    align 4
Simulate_Iret endp

;--- simulate an V86 Int
;--- INP: EBP -> Client_Reg_Struc
;--- INP: EAX == INT #
;--- modifies EAX, ECX, EDX

Simulate_Int proc

    mov edx,[eax*4]
    movzx eax,word ptr [EBP].Client_Reg_Struc.Client_ESP
    MOVZX ECX,word ptr [EBP].Client_Reg_Struc.Client_SS   ; get address of v86 SS:SP
    SUB AX, 3*2                 ; make room for IRET frame
    SHL ECX,4
    ADD ECX, EAX
    MOV [EBP].Client_Reg_Struc.Client_ESP,eax

    MOV EAX,[EBP].Client_Reg_Struc.Client_CS    ; get v86 CS:IP into EAX
    shl EAX, 16
    MOV AX,word ptr [EBP].Client_Reg_Struc.Client_EIP
    MOV [ECX+0],EAX

    MOV word ptr [EBP].Client_Reg_Struc.Client_EIP,DX   ;found in IVT
    SHR EDX,16
    MOV [EBP].Client_Reg_Struc.Client_CS,EDX

    MOV EAX,[EBP].Client_Reg_Struc.Client_EFlags; + v86 Flags
    MOV [ECX+4],AX              ; and store them onto v86 stack
    and AH,not (1+2)            ; clear TF+IF
    mov [EBP].Client_Reg_Struc.Client_EFlags,eax

    ret
    align 4
Simulate_Int endp

;--- pop the "back" bp from the client's stack

End_Nest_Exec proc public
    call Simulate_Far_Ret
    ret
    align 4

End_Nest_Exec endp

;--- exec a v86 int immediately
;--- EBP -> Client_Reg_Struc
;--- EAX = INT# to execute

Exec_Int proc

    call [vmm_service_table.pSimulate_Int]

Exec_Int endp   ;fall through

Resume_Exec proc public
    push [dwStackCurr]
    pushad
    mov [dwStackCurr],esp
    mov esp,ebp
    @v86popreg
    add ESP,4+4         ; skip call return + error code
    IRETD
    align 4
Resume_Exec endp

;--- this breakpoint is used to continue execution in protected-mode in a
;--- nested execution block after Resume_Exec

V86_Back proc
    add esp,4   ;skip return address
    popad
    pop     [dwStackCurr]
    ret
    align 4

V86_Back endp

;--- save client's state to EDI

Save_Client_State proc
    push esi
    push edi
    mov ecx,size Client_Reg_Struc/4
    mov esi, ebp
    rep movsd
    pop edi
    pop esi
    ret
    align 4
Save_Client_State endp

;--- restore client's state from ESI

Restore_Client_State proc
    push esi
    push edi
    mov ecx,size Client_Reg_Struc/4
    mov edi, ebp
    rep movsd
    pop edi
    pop esi
    ret
    align 4
Restore_Client_State endp

if ?VME
;--- set/reset the VME flag in CR4 if supported
;--- INP: AL[0] new state of flag

SetVME proc public
    test byte ptr [dwFeatures], 2        ;VME supported?
    jz @@novme
    @mov_ecx_cr4
    and al,1
    and cl,not 1
    or cl,al
    @mov_cr4_ecx
@@novme:
    ret
    align 4
SetVME endp

endif

;--- Int 15h handler
;--- to detect Ctrl-Alt-Del.
;--- it also hooks the BIOS A20 functions
;
Int15_Entry PROC public

    cmp ax,4F53h    ;DEL pressed?
    jz @@isdel
ife ?HOOK13
    cmp ax,9101h    ;diskette interrupt done?
    jz @@isfdirq
endif
if ?A20PORTS
    cmp ah,24h      ;A20?
    jz @@isa20
endif
@@v86mon:
    push 15h
    JMP V86_Monitor ;route interrupt to v86

if ?A20PORTS

;--- catch int 15h, ax=2400h and ax=2401h

@@isa20:
    cmp al,2
    jnb @@v86mon
    @DbgOutS <"Int 15h, ax=">,?A20DBG
    @DbgOutW ax,?A20DBG
    @DbgOutS <" called",10>,?A20DBG
 if 0
    call A20_Set ;al=0|1
    mov ah,0
    and [esp].IRETDV86.vEFL, not 1
 else
    mov ah,86h
    or [esp].IRETDV86.vEFL, 1
 endif
    iretd
endif

@@isdel:
    PUSH EAX
    MOV AL,CS:[@KB_FLAG]    ; Have the keys CTRL & ALT
    AND AL,1100B            ; been pressed ?
    CMP AL,1100B            ; If not,  continue working
    POP EAX
    JNZ @@v86mon
    push 0
    push 0                   ; push dummy values to get a Client_Reg_Struc frame
    @v86pushreg
    push ss
    pop ds
    push ss
    pop es
    mov esp,[dwStackCurr]
    cld
    call Begin_Nest_Exec
    mov eax,15h             ; call the v86 int15 hookers
    call Exec_Int
;   call End_Nest_Exec       ; not needed
;--- possibly one should check if the carry flag has been cleared
;--- by one of the hookers. Then reboot should NOT be done.

if 1
;--- v5.75: int 15h, ah=4Fh usually is called during an IRQ. Is the PIC
;---        waiting for an EOI? Has the keyboard been disabled?
    and word ptr ds:[@KB_FLAG],not 01100001100b ;reset Ctrl+Alt status
    and byte ptr ds:[496h],not 1111b            ;reset Ctrl,Alt,E0,E1 status
    mov al,0Bh      ;get ISR of MPIC
    out 20h,al
    in al,20h
    test al,02      ;IRQ 1 happened?
    jz @F
    mov al,20h      ;send EOI to PIC
    out 20h,al
@@:
    XOR ECX,ECX
@@: IN AL,64h       ;wait until kbd buffer is free
    TEST AL,02
    LOOPNZW @B
    MOV AL,0AEh     ;enable keyboard
    OUT 64h,AL
endif
    jmp Reboot

ife ?HOOK13
@@isfdirq:
    btr word ptr ss:[bDiskIrq],0
    jnc @@v86mon
    push ss
    pop ds
    push ss
    pop es
    call Dma_CopyBuffer
    jmp @@v86mon
endif

Int15_Entry ENDP

if ?UNLOAD

;--- unload Jemm
;--- this is invoked by a v86 breakpoint called by Jemm16
;--- EBP must be restored before exiting!
;--- the functions returns with a RETF to Jemm16, but stays
;--- in protected mode

Unload proc

    call Simulate_Far_Ret

if ?VME
    mov  al,0
    call SetVME
endif

if ?FREEXMS
    call Pool_FreeAllBlocks
endif

if ?UNLDBG
    @DbgOutS <"Reset, v86CS:EIP=">,1
    mov eax, [ebp].Client_Reg_Struc.Client_CS
    @DbgOutW ax,1
    @DbgOutS <":">,1
    mov eax, [ebp].Client_Reg_Struc.Client_EIP
    @DbgOutD eax,1
    @DbgOutS <", v86SS:ESP=">,1
    mov eax, [ebp].Client_Reg_Struc.Client_SS
    @DbgOutW ax,1
    @DbgOutS <":">,1
    mov eax, [ebp].Client_Reg_Struc.Client_ESP
    @DbgOutD eax,1
    @DbgOutS <10>,1
endif

;--- set base of REAL_CODE_SEL and REAL_DATA_SEL
;--- to the current v86 CS/SS

    mov ebx,offset V86GDT
    movzx eax, word ptr [ebp].Client_Reg_Struc.Client_CS
    shl eax, 4
    mov word ptr [ebx + REAL_CODE_SEL+2], ax
    shr eax, 16
    mov byte ptr [ebx + REAL_CODE_SEL+4], al
    movzx eax, word ptr [ebp].Client_Reg_Struc.Client_SS
    shl eax, 4
    mov word ptr [ebx + REAL_DATA_SEL+2], ax
    shr eax, 16
    mov byte ptr [ebx + REAL_DATA_SEL+4], al

;--- restore v86 interrupt vectors

    mov eax, [OldInt06]
    mov ds:[06h*4],eax
    mov eax, [OldInt19]
    mov ds:[19h*4],eax
if ?VDS
    call VDS_Exit
endif
    mov eax, [OldInt67]
    mov ds:[67h*4],eax

    mov edx, [ebp].Client_Reg_Struc.Client_EIP
    mov ecx, [ebp].Client_Reg_Struc.Client_ESP
    mov ebp, [ebp].Client_Reg_Struc.Client_EBP
ife ?INTEGRATED
    mov bx, [XMSCtrlHandle]
else
    mov bl, [A20Index]
endif

    push 0
    push word ptr 3FFh
    LIDT FWORD ptr [esp]     ; reset IDT to real-mode
    
    
    MOV AX,REAL_DATA_SEL    ; before returning, set the
    MOV DS,EAX              ; segment register caches
    MOV ES,EAX
    MOV FS,EAX
    MOV GS,EAX
    MOV SS,EAX
    mov ESP,ECX

;--- the rest will be done by the 16bit part

    push REAL_CODE_SEL
    push edx
    retf

Unload endp
endif

if ?FASTBOOT

;--- how is FASTBOOT implemented?
;--- the important thing is to restore the IVT to the values
;--- *before* DOS has been installed. This requires:
;--- a). DOS must hook int 19h and restore the vectors it has modified
;---     (vectors which count are 00-1F, 40-5F and 68-77). It must also
;---     save vector 15h (which is modified by himem.sys).
;--- b). the vectors must be saved at 0070:100h
;---     msdos saves at least 10,13,15,19,1B.
;--- c). jemm must be loaded as a device driver, so it is loaded very 
;---     early before other drivers/tsrs.
;--- if these requirements are met, Jemm will do with FASTBOOT: 
;--- 1. save int vectors 0-1F, 40-5F, 68-77 (20h+20h+10h = 50h*4=320 bytes)
;---    on init.
;--- 2. on ctrl-alt-del, restore these vectors, save the vector for int 19h
;---    which DOS has saved internally at 0070:0100+x and modify it to point
;---    to a breakpoint.
;--- 3. call v86-int 19h. DOS will restore the vectors it has saved.
;--- 4. Jemm regains control, with DOS already deactivated. Now clear
;---    vectors 20-3F, 60-67 and 78-FF, restore int 19h to the value saved 
;---    previously.
;--- 5. jump to real-mode and do an int 19h again.

restorevecs proc
    pushad
    xor eax, eax
    mov edi, eax
    mov esi, [pSavedVecs]
    push ds
    pop es
if ?RBTDBG
    @DbgOutS <"restoring vectors 00-1F, 40-5F, 68-77",10>,1
endif
    mov ecx, 20h
    rep movsd           ;set 00-1F
    add edi, 20h*4
    mov cl, 20h
    rep movsd           ;set 40-5F
    add edi, 8*4
    mov cl, 10h
    rep movsd           ;set 68-77

;--- search the int 19h vector stored at 0070:100h

    mov esi,700h+100h
    mov cl,5
@@nextitem:
    lodsb
    mov bl,al
    lodsd
    cmp bl,19h
    loopnz @@nextitem
    stc
    jnz @@norestore     ;not found. no FASTBOOT possible

    mov edx, [dwRSeg]
    shl edx, 16
    mov dl, [bBpTab]    ;use the first BP for returning to the monitor
if ?RBTDBG    
    @DbgOutS <"vector 19h saved by DOS=">,1
    @DbgOutD eax,1
    @DbgOutS <", temp vector=">,1
    @DbgOutD edx,1
    @DbgOutS <10>,1
endif
    mov [OldInt19],eax  ;save the vector stored by DOS
    mov [esi-4],edx

if 0    ;restoring the XBDA should be done by DOS (MS-DOS does)
    mov dx,ds:[40Eh]
    and dx,dx
    jz @@noxbda
    mov ax,ds:[413h]    ;move it to top of RAM
    dec eax
    mov ds:[413h],ax    ;should be 27Fh (=639 kb) again
    shl eax,6           ;27Fh -> 9FC0
    movzx esi,dx
    shl esi,4
    movzx edi,ax
    shl edi,4
    mov ecx, 400h/4
    rep movsd
@@noxbda:
endif

if 0
    in al,0A1h
    or al,03Fh
    out 0A1h,al
    in al,021h
    or al,0F8h
    out 21h,al
endif

    clc
@@norestore:
    popad
    ret
restorevecs endp

fastboot proc

    @DbgOutS <"fastboot reached",10>,?RBTDBG    

    mov al,0Bh
    out 20h,al
    in al,20h
    and al,al
    jz @@fb_1
    mov al,20h              ; send EOI to master PIC (for keyboard)
    out 20h,al
@@fb_1:
    mov al,0AEh             ; (re)enable keyboard
    out 64h,al

    call Begin_Nest_Exec
if 1
    @DbgOutS <"resetting PS/2 mouse",10>,?RBTDBG
    mov word ptr [ebp].Client_Reg_Struc.Client_EAX, 0C201h  ;reset PS/2 mouse
    mov eax,15h
    call Exec_Int
endif
    @DbgOutS <"calling restorevecs",10>,?RBTDBG
    call restorevecs
    jc Reboot_2

;--- (re)launch int 19h. this will make DOS restore vectors.
;--- since the int 19h value saved by DOS has been modified by Jemm,
;--- execution will reach fastboot_1 at last.

    @DbgOutS <"launching Int 19h",10>,?RBTDBG
    mov ds:[bptable.pInt06], offset fastboot_1
    mov eax,19h
    call Exec_Int
fastboot_1:

;--- now DOS has restored its vectors
;--- restore the previously modified int 19h vector

    @DbgOutS <"reached fastboot_1",10>,?RBTDBG
    mov eax,[OldInt19]
    mov ds:[19h*4],eax

if 0
    mov dword ptr ds:[1Eh*4],0F000EFC7h
endif

;--- the v86 space is now "without" DOS

;--- set vectors 20-3F, 60-67 and 78-FF

    push ds
    pop es
    mov edi,20h*4
    mov ecx,20h
    xor eax,eax
    rep stosd       ;20-3F
    add edi,20h*4
    mov cl,8
    rep stosd       ;60-67
    add edi,10h*4
    mov cl,8
    rep stosd       ;78-7F

if 1
    movzx ecx, word ptr ds:[40Eh]
    jecxz @@noxbda
    shl ecx, 4
    mov word ptr [ecx+90h],0    ;clear boot flags (might be BIOS specific)
@@noxbda:
endif

if ?RBTDBG
    mov ecx,20h
    xor esi,esi
    xor ebx,ebx
@@:
    lodsd
    @DbgOutB bl,1
    @DbgOutS <": ">,1
    @DbgOutD eax, 1
    @DbgOutS <"        ">,1
    inc ebx
    loop @B
    @DbgOutS <10>,1
;    @WaitKey 1,1
endif

    mov dl,1        ;set flag for fastboot
    jmp Reboot_1

fastboot endp
endif

Int19_V86Entry:

;   call Simulate_Iret  ;not needed since there is no return

;--- Reboot - reboot the machine

Reboot proc

    @DbgOutS <"Reboot enter",10>,?RBTDBG    

if ?FASTBOOT
    test [bV86Flags], V86F_FASTBOOT
    jnz fastboot
Reboot_2::
    mov dl,0    ;flag: do a "full" reboot
endif

Reboot_1::
    @DbgOutS <"Reboot_1 reached, int 19=">,?RBTDBG    
    @DbgOutD ds:[19h*4],?RBTDBG
    @DbgOutS <10>,?RBTDBG    

    MOV WORD PTR DS:[@RESET_FLAG],1234H ; 1234h=warm boot

if 1
    MOV AL,0Fh  ;disable NMI, set shutdown byte
    out 70h,al
    MOV AL,0    ;software-reset
    out 71h,al
endif

ife ?USETRIPLEFAULT
    mov edi, 7E00h
    mov esi, offset rmcode
    mov ecx, offset endofrmcode - offset rmcode
    push ds
    pop es
    rep movsb
  if ?FASTBOOT
    cmp dl,1
    jnz @@nofast2
    sub edi, 5
    mov esi, offset rmcode2
    mov ecx, offset endofrmcode2 - offset rmcode2
    rep movsb
    and byte ptr ds:[47Bh],not 20h  ;reset VDS bit
@@nofast2:
  endif
    xor edx, edx
    push edx
    push word ptr 3FFh
    LIDT FWORD ptr [esp]     ; reset the IDT to real-mode

  if 1
    cmp edx,[dwFeatures]
    jz @@nocr4
    @mov_cr4_edx                ; reset CR4 to 0
@@nocr4:
  endif

    MOV AX,REAL_DATA_SEL    ; before returning to real-mode set the
    MOV DS,EAX              ; segment register caches
    MOV ES,EAX
    MOV FS,EAX
    MOV GS,EAX
    MOV SS,EAX              ; set SS:ESP
    MOV ESP,7C00h
    MOV ECX,CR0             ; prepare to reset CR0 PE and PG bits
    AND ECX,7FFFFFFEH
    XOR EAX, EAX
    db 66h                 ; jmp REAL_CODE_SEL:7E00h
    db 0eah                ; (this sets CS attributes to 16bit
    Dw 7E00h               ; and FFFF limit)
    dw REAL_CODE_SEL
else
    xor edx,edx             ; cause a triple fault to reboot
    push edx
    push edx
    lidt fword ptr [esp]
    int 3
endif

rmcode:
    db 0Fh, 22h, 0C1h       ;7E03: mov cr0, ecx (switches to real-mode)
    db 0Fh, 22h, 0D8h       ;7E00: mov cr3, eax
    db 8Eh, 0D0h            ;7E06: mov ss, ax (set SS=0000)
    db 0EAh,0, 0, -1, -1    ;7E08: jmp ffff:0000 (set CS=FFFF)
                            ;7E0D:
endofrmcode:
if ?FASTBOOT
rmcode2:
    db 0EAh,0Dh,7Eh,0, 0    ;jmp 0000:7E0D (set CS=0)
if ?RBTDBG
    db 0B8h, 52h, 0Eh       ;mov ax,0e52h
    db 0BBh, 07h, 00h       ;mov bx,0007h
    db 0CDh, 10h            ;int 10h
    db 0B8h, 42h, 0Eh       ;mov ax,0e42h
    db 0CDh, 10h            ;int 10h
    db 0B8h, 54h, 0Eh       ;mov ax,0e54h
    db 0CDh, 10h            ;int 10h
endif
if 0
    db 0Eh                  ;push cs
    db 1Fh                  ;pop ds
    db 0Eh                  ;push cs
    db 07h                  ;pop es
    db 0FBh                 ;sti
    db 0B8h, 00h, 00h       ;mov ax,0000h
    db 0BAh, 80h, 00h       ;mov dx,0080h
    db 0CDh, 13h            ;int 13h
    db 0B8h, 01h, 02h       ;mov ax,0201h
    db 0B9h, 01h, 00h       ;mov cx,0001h
    db 0BAh, 80h, 00h       ;mov dx,0080h
    db 0BBh, 00h, 7Ch       ;mov bx,7C00h
    db 0CDh, 13h            ;int 13h
    db 06h                  ;push es
    db 53h                  ;push bx
    db 0CBh                 ;retf
else
    db 0CDh, 19h            ;int 19h
endif
endofrmcode2:
endif

Reboot endp

    align 4

if ?SERVTABLE

vmm_service_table label VMM_SERV_TABLE
    dd Simulate_Int
    dd Simulate_Iret
    dd Simulate_Far_Call
    dd Simulate_Far_Ret
    dd Begin_Nest_Exec
    dd Exec_Int
    dd Resume_Exec
    dd End_Nest_Exec
    dd Simulate_IO
    dd Yield
    dd VDS_Call_Table
    dd VCPI_Call_Table
    dd IO_Trap_Table
    dd V86_Monitor
    dd offset dwStackCurr
    dd MoveMemory

endif

.text$03 ends

    END _start
