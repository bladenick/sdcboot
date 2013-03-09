 ; This file is part of LBAcache, the 386/XMS DOS disk cache by
 ; Eric Auer (eric@coli.uni-sb.de), 2001-2004.

 ; LBAcache is free software; you can redistribute it and/or modify
 ; it under the terms of the GNU General Public License as published
 ; by the Free Software Foundation; either version 2 of the License,
 ; or (at your option) any later version.

 ; LBAcache is distributed in the hope that it will be useful,
 ; but WITHOUT ANY WARRANTY; without even the implied warranty of
 ; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 ; GNU General Public License for more details.

 ; You should have received a copy of the GNU General Public License
 ; along with LBAcache; if not, write to the Free Software Foundation,
 ; Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 ; (or try http://www.gnu.org/licenses/licenses.html at www.gnu.org).


; Central cleverness part of LBACACHE, included by BINSEL.
; Please read BINSEL2.TXT for more information.

; Version of 12 Nov 2002, by Eric Auer eric@coli.uni-sb.de
; used "search all" findbin and "write to all, preferably near
; most recently used" newbin. More flexible, less spilling.

; Version of 15 Nov 2002 is reintroducing speed, flexibility is
; not everything. Means: a bonustable and MEMOIZATION, and the
; ability to remember the most recently asked for bin even faster.

; *** WARNING: binsel.asm must fill the "bonustable" with pointers
; *** to "table" in flush, otherwise you get chaos! To be found in
; *** lbacache.asm: the install code fills all memory from table
; *** to end of stack with " " and then calls flush (in binsel.asm).
; *** setup.asm writes out int 0x13 moments before that. The actual
; *** mov running,1 happens at the very last moment of lbacache.asm!

; %define FULLYASSOC 1		; define for 5/2004 fully assoc cache
				; changed to command line option 7/2004
				; (if tuneflags & 1 --> fully assoc!)

; %ifndef FULLYASSOC		; <<<< fully versus N way associative
%define ASSOCWAYS 16		; N way assoc cache (6/2004 style)
				; *** read below for values > 16 ***
; %endif			; <<<< associativity

; macro BINBCHECK ARG does (all registers preserved):
; ARG [ds:si+6],bit 1 shl (al and BINBITS)
; where ARG can for example be OR or TEST

	; Table format: each 8 byte main bin is a struct:
	; DWORD EAX of sector
	; BYTE  DL  of sector
	; BYTE  free for your findbin/newbin
	; WORD  bitmask: if bit N is set, sector EAX+N is in use

	; *** New: remember last question/answer (11/2002)
	; (for findbin)

fbPOINT		dw table	; pointer into table
	; *** must be initialized! "where findbin last found" pointer

; --------------

	; calculates a pointer DI into memoization array: index
	; is hash(EAX xor byte ARG1) in bonustable. Destroys EAX.
%imacro MEMOHASH 1
	xor al,%1	; xor in drive number
	xor al,ah	; start hashing
	rol eax,8	; get high byte
	xor al,ah	; xor in already known stuff
	rol eax,8	; get 3rd byte
	xor al,ah	; done with hashing
	xor ah,ah	; movzx ax,al
	shl ax,1	; 1 word per memoization item
	mov di,[cs:bonustable]	; memoization array!
	add di,ax	; pointer to entry in memoization array
%endmacro


MEMOIZE:  push eax	; add entry at SI to memoization list
	  push di
	mov eax,[cs:si]
	MEMOHASH [cs:si+5]	; find memoization array pointer
	mov [cs:di],si		; memoize the fbPOINT there
	  pop di
	  pop eax
	ret

	; the trick with the memoization list is that it is
	; sorted by hash of sector number and drive number:
	; you either get the right entry without searching
	; or it is not in the memoization list at all. It is
	; no real problem that new entries overwrite old ones.

; --------------

; --------------

findbin:	; find bin matching location EAX DL,
	push ds	; return carry or bin in AX (and update LRU)
	  push cs
	  pop ds	; avoid extra CS: prefixes...
	push si
	push cx

	mov si,[cs:fbPOINT]	; try same point as last time
	  push eax
	and al,BINMASK	; ignore low part
	cmp eax,[si]	; compare sector number
	  pop eax
	jnz realfindbin
	cmp dl,[si+4]	; compare drive number
	jnz realfindbin

fbsamebin:		; bin as before, can only be success/miss
	jmp fbcommit_nomemoize

; -------------

realfindbin:
REMEMOIZE:	; next stage: check in MEMOIZE list!
	mov cx,di	; * save di
	push eax
	MEMOHASH dl	; calculate pointer to memozation item...
	pop eax
	mov si,[cs:di]	; read memoized fbPOINT value
	mov di,cx	; * restore di

	cmp si,table		; label! *** in range?
	jb  UNREMEMOIZE
	cmp si,[cs:tableend]	; *** in range?
	jae UNREMEMOIZE		; (could also check alignment)
	cmp eax,[ds:si]		; correct entry memoized?
	jnz UNREMEMOIZE
	cmp dl,[ds:si+4]	; correct entry memoized?
	jnz UNREMEMOIZE

	; Yeah, we found the needed entry back at once. :-)
	jmp short fbcommit	; commit to that entry :-)

	; Still not found, we have to search the array! :-(
UNREMEMOIZE:	

; -------------

; %ifdef FULLYASSOC		; <<<< fully versus N way associative

	mov cl,[cs:tuneflags]	; new 7/2004: command line selectable
	test cl,1		; fully assoc selected?
	jz unrememoize_nway

unrememoize_full:

	mov si,table		; table start
	mov cx,[cs:sectors]	; table size, in subbins
				; *** WAS BUGGY ***
	shr cx,BINSHR		; table size in main bins
				; (dumb and slow: search whole table)
	jmp short unrememoize_common

; %else				; <<<< else N way associative

unrememoize_nway:

	call hashme		; find preferred SI for EAX.DL
	push si			; STUPID bug 6/2004 - was push ax
	add si,8*ASSOCWAYS	; too close to table end?
	cmp si,[cs:tableend]	; [tableend] is first byte after table
	pop si			; STUPID bug 6/2004 - was pop ax
	jbe hashinrange		; no, everything fine	; jbe, not jb!
	mov si,[cs:tableend]	; else select a smaller SI
	sub si,8*(ASSOCWAYS)				; not ... +1 !
	; *** Will cause havoc if less than ASSOCWAYS entries in ***
	; *** table. 16 entries are safe to assume (128k/8k=16). ***

hashinrange:
	mov [cs:hashwhere],si	; buffer the value (used for newbin)
	mov cx,ASSOCWAYS	; how many bins to search at most

unrememoize_common:

; %endif			; <<<< associativity

	  push ax	 	; THE save
	and al,BINMASK	 	; <- only search for MAIN bin

	align 4
findbinscan:
	cmp eax,[si]	 ; *	; sector number "same enough"?
	jz short fbtry   ; *	; then check DL as well
fbscan:	lea si,[si+8]	 ; *	; not the right bin? scan on!
	loop findbinscan ; *	; loop over all main bin entries
	jmp short fbnope 	; did not find Bin (Laden?) anywhere
				; George will be disappointed!
fbtry:	cmp dl,[si+4] 	 ; +	; drive also the same?
	jz short fbcom2	 ; +	; then commit to that bin :-)
	jmp short fbscan ; +

	; The 4 "*" instructions are a loop with max 7500 iter-
	; ations, or ASSOCWAYS iterations in non-FULLYASSOC mode.
	; The 3 "+" instructions are hit max 2+8 times, if the
	; sector is always right but drive number is never.

fbnope:	  pop ax		; ONE restore
	mov ax,-1		; return value
	; *** neither AX nor SI are remembered in that case ***
	jmp short fbmiss	; when exhausted, report real MISS

fbcom2:	  pop ax		; OTHER restore
	
fbcommit:	; commited to this bin, can only be hit or miss now!
	mov [cs:fbPOINT],si	; *** remember for next findbin ***
	call MEMOIZE		; * add entry at SI to memoized list *
				; store tab_si at memo/hash(tab/[si])
fbcommit_nomemoize:
	BINBCHECK test	; <- a macro... return NZ if bin is filled
	jnz foundbin		; we found it!

	sub si,table		; at least return main bin which
	shr si,3		; would be the one to go! NEW 11/2002
	shl si,BINSHR		; shl is correct here!
	mov ax,si		; *** return value ***
	jmp short fbmiss	; only one main bin possible, must
	; be a real MISS here. Return main bin, but set CARRY flag.

foundbin:
	cmp byte [ds:si+5],0xfe	; check LRU / importance and
	jae fbmax		; increase it (with saturation at -2)
	inc byte [ds:si+5]
fbmax:	sub si,table
	shr si,3	; each table entry is 8 (EIGHT) byte, 64 bit
	shl si,BINSHR	; main entries -> sub entries (shl is correct)
	and ax,BINBITS	; *** bin LSB are taken from sector number
	add ax,si	; *** now we have the correct SUB ENTRY / BIN
%ifdef BSDEBUGFB
		push word fbdbgmsgNC
		call meep
%endif
	clc		; indicate success
	call WATCH_TEMPERATURE	; new 9/2004
	jmp short fbout	; return the bin found (in AX)

fbmiss:
%ifdef BSDEBUGFB
		push word fbdbgmsgCY
		call meep
%endif
	stc		; indicate failure

fbout:	pop cx
	pop si
	pop ds
	ret

; -------------

; **************************************************************

; -------------

newbin:		; find a new free bin or reuse a bin
		; for location EAX DL. update LRU, return bin in AX
	push ds
	  push cs
	  pop ds	; helps us to avoid CS: prefixes
	push si
	mov si,ax	; * [[]] save sector low word for later (AX->SI)

	call findbin	; try to find an existing main bin
			; IF one exists, LRU is updated now

	jnc nbret2	; Surprise: There WAS a bin, no newbin needed!
			; (so we return that bin in AX)
	cmp ax,-1	; did not even find a related bin?
			; Then we do NOT return any useful AX - instead, we
			; search ALL cache (or if 16 way assoc, 16 elements)!
	jz near nbreal	; then we need to allocate a NEW main bin!
			; Important: In THIS case, dw hashwhere got
			; initialized in findbin: memo-lookup failed.

; -------------

	; case: only need to fill sub of known matching main bin
nbpart: push si		; * [[]] save sector low word (as saved AX->SI)
	shr ax,BINSHR	; convert from sub bin number
	shl ax,3	; *** convert into table offset ***
	add ax,table	; label! Now we have the main bin pointer
	mov si,ax	; for the already existing main bin in SI
	pop ax		; * [[]] restore sector low word (now AX again)
	BINBCHECK or	; set the appropriate bit
%ifdef BSDxNB
		push word nbdbgseclo
		call meep
%endif

nbreturn:		; calculate AX given SI (table point)
			; and EAX (sector number, for sub-bin)
	mov [cs:fbPOINT],si	; assume findbin to there soon
	call MEMOIZE		; * add entry at SI to memoized list *
				; store tab_si at memo/hash(tab/[si])
	;
			; Same idea as fbmax... but other POPs / messages
	sub si,table	; label!
	shr si,3	; *** convert back to table index ***
	shl si,BINSHR	; convert back to sub bin number
	and ax,BINBITS	; *** 
	add ax,si	; *** now we have the sub bin number
	call WATCH_TEMPERATURE	; new 9/2004

nbret2:	
%ifdef BSDxNB
		push word nbdbgmsg
		call meep
%endif
	pop si
	pop ds
	ret

; -------------

; %ifdef FULLYASSOC		; pointer for round-robin allocation
nbwhere		dw table	; current search pointer for allocation
; %else
hashwhere	dw table	; current search start pointer of last findbin
; %endif			; nbwhere and hashwhere are never used at
				; the same time - could save 2 bytes here.

%ifdef BSDEBUGNB
%ifdef BSDxNB
nbdbgmsg		db " NewBin=",0
nbdbgseclo		db " NewBinSecLo=",0
%endif
nbdbgskipfrozen	db " NewBinSkipFrozen/",0
nbdbgreplace	db " NewBinReplaceP=",0
%endif
%ifdef BSDEBUGFB
fbdbgmsgCY	db " FindBinCY=",0
fbdbgmsgNC	db " FindBinNC=",0
%endif

	; case: start or overwrite a fresh main bin!
nbreal:	mov ax,si	; * [[]] restore EAX.DL here (as saved AX->SI)


; %ifdef FULLYASSOC		; <<<< fully versus N way associative

	test byte [cs:tuneflags],1	; new 7/2004: command line selectable
	jz nbreal_nway			; fully assoc selected?

nbreal_full:

nbwcheck:
	mov si,[cs:nbwhere]	; XX search pointer in range?
; ---	cmp si,table		; XX label!
; ---	jb nbwbug		; XX too small?
	cmp si,[cs:tableend]	; XX
	jb nbwok		; XX too big?
nbwbug:	mov si,table		; XX label! ...else wrap to start
	mov [cs:nbwhere],si	; XX

nbwok:			; now SI is our current allocation pointer
	add word [cs:nbwhere],8	; XX next main entry for search point
			; (wrapping will be done in next iteration)

	cmp byte [ds:si+5],255	; XX entry frozen?
	jb nboverwrite		; XX otherwise just use it :-)
%ifdef BSDEBUGNB
		push word nbdbgskipfrozen
		call meep
%endif
	jmp short nbwcheck	; XX do range check again

; %else				; <<<< else N way associative

nbreal_nway:

	push ax
	push bx
	push cx
	mov si,[cs:hashwhere]	; reload search start pointer stored
				; by the findbin call just a moment ago
	lea si,[si+5]		; point to LRU byte
	mov bx,si		; if nothing better found, use the bin
				; where the search starts now...
	mov cx,ASSOCWAYS	; how many bins to search at most
	mov ah,254		; prefer finding a non-frozen bin

	align 8
bestalloc:
	mov al,[si]	; *	; check LRU
	cmp al,ah	; *	; less important bin found?
	jb betterbin	; *	; then update "best bin so far" etc.
searchalloc:
	lea si,[si+8]	; *	; move on to next bin
	loop bestalloc	; *	; stop trying to improve after a while
thisalloc:
	lea si,[bx-5]		; rewind: LRU offs BX -> bin offs SI
	pop cx
	pop bx
	pop ax
	jmp short nboverwrite	; this bin at SI will be our victim!

betterbin:
	mov bx,si	 ; +	; better use this bin, has smaller LRU
	mov ah,al	 ; +	; update "best LRU found so far" value
	cmp al,1	 ; +	; unused bin? (use ,4 for "little used...")
	jb thisalloc	 ; +	; then stop searching earlier
	jmp short searchalloc	; + keep searching for less used bins

	; The 5 commands of * are done ASSOCWAYS times,
	; the 5 commands of + are done at most ASSOCWAYS times.

; %endif			; <<<< associativity


nboverwrite:
%ifdef BSDEBUGNB
	cmp byte [ds:si+5],0	; entry empty?
	jz nbharmless		; skip message then
	push ax
	mov ax,si
		push word nbdbgreplace
		call meep
	pop ax
nbharmless:
%endif
	mov [ds:si],eax		; store sector number in table
	and byte [ds:si],BINMASK	; <- ADJUST
	mov [ds:si+4],dl	; store drive number in table
	mov byte [ds:si+5],1	; initialize LRU / importance with 1
	mov word [ds:si+6],0	; initialize bitmask as empty
	BINBCHECK or		; activate bit in bitmask
	jmp nbreturn		; calculate return value and return
				; (also update memoization and fbpoint!)

; -------------

WATCH_TEMPERATURE:			; function added 9/2004
	pushf
	cmp ax,-1
	jz nowatch_temperature
	cmp byte [cs:temperature],0	; 0 normal, 1 melt, -1 freeze
	jg do_melt			; signed!
	jl do_freeze			; signed!
nowatch_temperature:
	popf
	ret

do_melt:
	call meltbin
;		push word xxxmsg
;		call meep
	jmp short nowatch_temperature
do_freeze:
	call freezebin
;		push word yyymsg
;		call meep
	jmp short nowatch_temperature


; xxxmsg	db "melting=",0
; yyymsg	db "freezing=",0
