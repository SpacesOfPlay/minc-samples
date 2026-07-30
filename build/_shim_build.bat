@call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul
cl /nologo /c /GS- /Fo:"C:\Users\mattias\sopgit\minc-samples\build\shim_demo_win.obj" "C:\Users\mattias\sopgit\minc-samples\shim_demo.c" >nul 2>&1

