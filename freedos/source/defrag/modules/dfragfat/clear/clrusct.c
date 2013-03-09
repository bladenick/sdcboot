/*    
   ClrUSct.c - routine to clear the free space in a volume.

   Copyright (C) 2002 Imre Leber

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

   If you have any questions, comments, suggestions, or fixes please
   email me at:  imre.leber@worldonline.be
*/

#include <stdlib.h>
#include <string.h>

#include "fte.h"

static BOOL UnusedSectorClearer(RDWRHandle handle, CLUSTER label,
                                SECTOR datasector, void** structure);

BOOL ClearUnusedSectors(RDWRHandle handle)
{
    return LinearTraverseFat(handle, UnusedSectorClearer, NULL);
}

static BOOL UnusedSectorClearer(RDWRHandle handle, CLUSTER label,
                                SECTOR datasector, void** structure)
{
  SECTOR sector;
  char sectbuf[BYTESPERSECTOR];

  structure = structure;
  
  memset(sectbuf, 0xfd, BYTESPERSECTOR); 
    
  if (FAT_FREE(label))
  {
     for (sector = 0; sector < GetSectorsPerCluster(handle); sector++)
         if (!WriteDataSectors(handle, 1, datasector+sector, sectbuf))
            RETURN_FTEERR(FAIL);
  } 
  
  return TRUE;
}
