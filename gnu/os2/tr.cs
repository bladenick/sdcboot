(-W1 -Za -Ios2 -Ilib -DSTDC_HEADERS -DUSG -DOS2
src\tr.c
)
setargv.obj
os2\textutil.def
out\textutil.lib
out\tr.exe
-AS -LB -S0x2000
