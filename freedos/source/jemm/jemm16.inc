
;--- globals for jemm.asm and jemm16.asm

?INITRMDBG  equ 0   ;log real-mode init
?XMSRMDBG   equ 0   ;log XMS calls
?EMXRMDBG   equ 0   ;log EMMXXXX0 calls
?UNLRMDBG   equ 0   ;log unload
?RMDBG      equ ?INITRMDBG + ?XMSRMDBG + ?EMXRMDBG + ?UNLRMDBG  ; debug displays in real-mode

if ?INTEGRATED
NAMEEXE equ <"JEMMEX">
NAMEMOD equ <"JemmEx">
else
NAMEEXE equ <"JEMM386">
NAMEMOD equ <"Jemm386">
endif

?RSEG equ 1 		; 1 = use separate RSEG segment

_TEXT16 group _TEXT

;--- modes for mainex()
EXECMODE_SYS equ 0	;launched as dos device driver
EXECMODE_EXE equ 1	;launched as application

InitJemm proto c
IsJemmInstalled proto c
EmmInstallcheck proto c
XMSinit proto c
CheckIntHooks proto stdcall :WORD
UnloadJemm proto c
VPRINTSTR proto
if ?INTEGRATED
I15SetHandle proto c
I15AllocMemory proto stdcall :WORD, :DWORD
endif

mainex proto c :WORD, :ptr BYTE

printf proto c :ptr byte, :VARARG
strlen proto c :ptr BYTE
memset proto c :ptr BYTE, :WORD, :WORD
_memicmp proto c :ptr BYTE, :ptr BYTE, :WORD

externdef c jemmini:JEMMINIT
externdef c XMSdriverAddress:far16 ptr
externdef c sig1:BYTE
externdef c sig2:BYTE

if ?INTEGRATED
externdef c xms_num_handles:WORD
endif
