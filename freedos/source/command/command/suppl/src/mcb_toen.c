/*
    This file is part of SUPPL - the supplemental library for DOS
    Copyright (C) 1996-2000 Steffen Kaiser

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public
    License along with this library; if not, write to the Free
    Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/
/* $RCSfile: mcb_toen.c,v $
   $Locker:  $	$Name:  $	$State: Exp $

ob(ject): mcb_env
su(bsystem): mcb
ty(pe): UM
sh(ort description): Return the environment of a PSP
lo(ng description): Returns the environment segment of the
	specified MCB.
pr(erequistes): \para{mcb} must point to a valid PSP
va(lue): Contents of the field "Associated Environment" of the PSP
re(lated to): 
se(condary subsystems): 
bu(gs): 
co(mpilers): 

*/

#include "initsupl.loc"

#include <portable.h>
#include "mcb.h"

#include "suppldbg.h"

#ifdef RCS_Version
static char const rcsid[] = 
	"$Id: mcb_toen.c,v 1.1 2006/06/17 03:25:06 blairdude Exp $";
#endif

#undef mcb_env
word mcb_env(const word mcb)
{	assert(isPSP(mcb));
	return peekw(mcb, SEG_OFFSET + 0x2c);
}
