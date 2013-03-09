/*    
        {
        }
   Msdefint.c - main code for interactive interface.

   Copyright (C) 2000 Imre Leber

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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dos.h>

#include "fte.h"
#include "..\..\modlgate\defrpars.h"
#include "..\..\modlgate\modlgate.h"
#include "..\..\misc\version.h"
#include "..\..\misc\misc.h"
#include "..\..\misc\reboot.h"
#include "..\..\misc\bool.h"
#include "..\keyboard\keyboard.h"
#include "..\mouse\mouse.h"
#include "..\event\event.h"
#include "..\screen\screen.h"
#include "..\screen\scrmask.h"
#include "..\dialog\dialog.h"
#include "..\dialog\menu.h"
#include "..\dialog\msgbxs.h"
#include "..\dialog\copyrigt.h"
#include "..\dialog\maplegnd.h"
#include "..\dialog\defrdone.h"
#include "..\dialog\AskFrXMS.h"
#include "..\winman\window.h"
#include "..\winman\winman.h"
#include "..\winman\control.h"

#include "..\helpsys\idxstack.h"
#include "..\helpsys\hlpparse.h"
#include "..\helpsys\hlpread.h"

#include "..\logman\logman.h"

#include "actions.h"
#include "keepdos.h"
#include "..\..\environ\checkos.h"
#include "chkargs.h"
#include "..\..\modlgate\callback.h"
#include "..\ovlhost\ovlimpl.h"

#include ".\..\environ\extmem.h"
#include "..\..\environ\xmsinst.h"

#define CHECKOS
#define CHECKEXTMEM
#define RELEASE

static void MainLoop(void);
static int  HandleMenu (void);
static void cdecl OnExit(void);
static int  cdecl OnCBreak (void);

#ifdef CHECKOS
static int  CheckOS(void);
#endif

int StartOptimization(void);

static char* HelpFileString = HELPFILE;
static struct CallBackStruct CallBacks;


int MSDefint(int argc, char *argv[])
{
    char* buttons[] = {"Ok"};
    char switchchar = SwitchChar();

    /* Check parameters. */
    ParseInteractiveArguments(argc, argv, switchchar);

    /* Initialise defrag. */
    SaveDOSState();
    atexit(OnExit);
    ctrlbrk(OnCBreak);
    MousePresent();
    SetScreenLines(25);
    ShowMouse();
    HideCursor();
    MouseGotoXY(1, 1);
    SetHighIntensity(1);
    CriticalHandlerOn();

     /* Initialise and start the sector cache */
    InitSectorCache();
    StartSectorCache();

    MSDEFINT_GetCallbacks(&CallBacks);
    SetCallBacks(&CallBacks);    

    /* Show copyright on the log. */
    LogPrint("This program is free software. It comes with ABSOLUTELY NO WARANTIES.\n"
             "You are welcome to redistribute it under the terms of the\n" 
             "GNU General Public License, see http://www.GNU.org for details.\n");

    CheckHelpFile(HelpFileString);

    /* Draw main screen. */
    DrawScreen();

#ifdef CHECKOS
    /* Check OS. */
    if (!CheckOS()) return 1; 
#endif
    
#ifdef CHECKEXTMEM

    if ((GetExtendedMemorySize() > 0) &&
   (!IsXMSInstalled()))
    {
   /* Give message and quit if necessary */
   if (AskForXMSManager()) return 0;
    }
    
#endif

#if 1    
    /* Ask for a drive and see wether it needs defragmentation. */
    if (GetParsedDrive() == 0)
    {
       if (SelectDrive()) 
       {
          if (StartOptimization()) 
             return 0;
       }
       else
          if (HandleMenu()) return 0;
    }
    else
    {
       DrawCurrentDrive(GetParsedDrive());
       if (!SetOptimizationDrive(GetParsedDrive()))
       {
          ErrorBox("Disk corrupted, cannot defragment!", 1, buttons);    
          return 0;
       }       
     
       if (QueryDisk()) 
       {        
          if (StartOptimization())
             return 0;
       }
       else
          if (HandleMenu()) return 0;
    }
#endif
    /* Go defrag! */
    PushHelpIndex(0);
    MainLoop();
    PopHelpIndex();

    return 0;
}


static void MainLoop()
{
    int leave = 0, event, refreshstatus = 1;

    while (!leave)
    {
        if (refreshstatus)
        {
           SetStatusBar(RED, WHITE, "                                            ");
           SetStatusBar(RED, WHITE, " Press ALT or F10 to activate menu.");
           refreshstatus = 0;
        }

        while ((event = GetEvent()) == 0);

        CheckExternalEvent(event);

        switch (event)
        {
            case ALT_B:
                 if (StartOptimization()) leave = TRUE;
                 refreshstatus = TRUE;
                 break;

            case ALT_L:
                 ShowMapLegend();
                 refreshstatus = TRUE;
                 break;

            case ALT_C:
                 ShowCopyRight();
                 refreshstatus = TRUE;
                 break;

            case ALT_X:
                 leave = TRUE;
                 break;

            case ALT_O:
            case F10:
            case ALTKEY:
                 leave = HandleMenu();
                 refreshstatus = TRUE;
                 break;

            case ALT_S:
                 SelectSortOptions();
                 refreshstatus = TRUE;
                 break;

            case ALT_M:
                 SelectOptimizationMethod();
                 refreshstatus = TRUE;
                 break;
            
            case MSLEFT:
            case MSRIGHT:
            case MSMIDDLE:
                 if (PressedInRange(3, 1, 15, 1))
                    leave = HandleMenu();
                 if (PressedInRange(63, 25, 80, 25))
                    ShowCopyRight();
                 refreshstatus = TRUE;
                 break;

            default:
                    while (AltKeyDown());
        }
    }
}

static int HandleMenu ()
{
    for (;;)
    {
       switch (MainMenu())
       {
              case CHANGEDRIVE:
                   if (SelectDrive()) 
                   {
                      if (StartOptimization()) return 1;
                   }
                   break;

              case EXITDEFRAG:
                   return 1;

              case DISPLAYCOPYRIGHT:
                   ShowCopyRight();
                   break;

              case SHOWMAP:
                   ShowMapLegend();
                   break;

              case SPECIFYFILEORDER:
                   SelectSortOptions();
                   break;

              case CHANGEMETHOD:
                   SelectOptimizationMethod();
                   break;

              case BEGINOPTIMIZATION:
                   if (StartOptimization()) return 1;
                   break;

              default:
                   return 0;
       }           
    }   
    /*return 0;*/
}

static int StartOptimization(void)
{
    int SkipDefragDone;
    
    DrawFunctionKey(3, "stop");
    SkipDefragDone = BeginOptimization();
    
    if (IsRebootRequested())
    {
       DOSWipeScreen();
       ColdReboot();     
    }
    else if (MustAutomaticallyExit())  
    {
       return 1;  
    }
    
    DrawFunctionKey(1, "help");
               
    if (!SkipDefragDone)
    {
   switch (ReportDefragDone())
   {
      case REBOOT_COMPUTER:
      DOSWipeScreen();
      ColdReboot();    /* Doesn't return */

      case EXIT_DEFRAG:
      return 1;
   }
    }

    ClearStatusBar();
    DrawTime(0, 0, 0);
    
    if (!SkipDefragDone)
    {
       UpdateDriveMap();
    }
    
    return 0;
}

static void cdecl OnExit()
{
      /* Reinitialise mouse-driver. */
      CloseMouse();

      DOSWipeScreen();

      /* Show the cursor. */
      RestoreDOSState();

      /* Release help system memory. */
      FreeHelpSysData();

      /* Stop the sector cache */
      StopSectorCache();
      
      /* Release all memory used by the cache */
      CloseSectorCache();
}

static int cdecl OnCBreak ()
{
      return 1;
}

#ifdef CHECKOS

static int CheckOS(void)
{
      char* msg;
      char* buttons[] = {"OK"};

      msg = CheckDefragEnvironment();
      if (msg)
      {
         ErrorBox(msg, 1, buttons);
         return FALSE;
      }
      
      return TRUE;
}

#endif
