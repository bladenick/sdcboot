(-W1 -Za -Ios2 -Ilib -DSTDC_HEADERS -DUSG -DOS2
src\head.c
)
setargv.obj
os2\textutil.def
out\textutil.lib
out\head.exe
-AS -LB -S0x8000
