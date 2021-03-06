/*	$Id: vcgetstr.c,v 1.4 2006/06/12 04:55:42 blairdude Exp $

	get a visual character that must match one of the supplied ones

	This file bases on MISC.C of FreeCOM v0.81 beta 1.

	$Log: vcgetstr.c,v $
	Revision 1.4  2006/06/12 04:55:42  blairdude
	All putchar's now use outc which first flushes stdout and then uses write to write the character to the console.  Some potential bugs have been fixed ( Special thanks to Arkady for noticing them :-) ).  All CONIO dependencies have now been removed and replaced with size-optimized functions (for example, mycprintf, simply opens "CON" and directly writes to the console that way, and mywherex and mywherey use MK_FP to access memory and find the cursor position).  FreeCOM is now
	significantly smaller.
	
	Revision 1.3  2006/06/11 02:47:05  blairdude
	
	
	Optimized FreeCOM for size, fixed LFN bugs, and started an int 2e handler (which safely fails at the moment)
	
	Revision 1.2  2004/02/01 13:52:17  skaus
	add/upd: CVS $id$ keywords to/of files
	
	Revision 1.1  2001/04/12 00:33:53  skaus
	chg: new structure
	chg: If DEBUG enabled, no available commands are displayed on startup
	fix: PTCHSIZE also patches min extra size to force to have this amount
	   of memory available on start
	bugfix: CALL doesn't reset options
	add: PTCHSIZE to patch heap size
	add: VSPAWN, /SWAP switch, .SWP resource handling
	bugfix: COMMAND.COM A:\
	bugfix: CALL: if swapOnExec == ERROR, no change of swapOnExec allowed
	add: command MEMORY
	bugfix: runExtension(): destroys command[-2]
	add: clean.bat
	add: localized CRITER strings
	chg: use LNG files for hard-coded strings (hangForEver(), init.c)
		via STRINGS.LIB
	add: DEL.C, COPY.C, CBREAK.C: STRINGS-based prompts
	add: fixstrs.c: prompts & symbolic keys
	add: fixstrs.c: backslash escape sequences
	add: version IDs to DEFAULT.LNG and validation to FIXSTRS.C
	chg: splitted code apart into LIB\*.c and CMD\*.c
	bugfix: IF is now using error system & STRINGS to report errors
	add: CALL: /N
	
 */

#include "../config.h"

#include <assert.h>
#include <conio.h>
#include <ctype.h>
#include <string.h>
#include <io.h>
#include <stdio.h>

#include "../include/command.h"
#include "../include/misc.h"

int vcgetcstr(const char *const legalCh)
{	int ch;

	assert(legalCh);

	fflush(stdout);               /* Make sure the pending output arrives the
								   screen as we bypass the stdio interface */
	while ((ch = vcgetchar()) == 0 || !strchr(legalCh, ch))
		beep();                     /* hit erroreous character */
	outc('\n');                /* advance to next line */
	return ch;
}
