@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
title PDF page splitter v2.4 - by XiaoNanSanSui @xiaonansansui

rem ===========================================================================
rem  PDF page splitter  v2.4
rem  Author        : XiaoNanSanSui
rem  GitHub        : https://github.com/xiaonansansui
rem  ------------------------------------------------------------------------
rem  What it does
rem    * opens a PDF and pulls every page image out of it
rem    * saves them as  1.jpg  2.jpg ...  (as "N.jpg") next to the PDF,
rem      inside  OUT_DIR\pdf name\  in the folder that holds the PDF
rem    * writes a matching one page A4 PDF for every image ("N.pdf")
rem    * rotates lying / upside down scans back to upright automatically
rem    * skips the page header template image that repeats on every page
rem  How to use
rem    1) double click this file, then drag PDF files into the window and
rem       press Enter (the window stays open, drop as many as you like)
rem    2) or drop PDF files / folders directly onto this file icon
rem    3) command line:  this.bat "file_or_folder" [-o outdir] [--name tpl]
rem                      [--open] [--jpg-only]
rem  Name template (--name)
rem    {n} {nn} {page} {pdf} {date} are replaced per image, for example
rem      --name "meeting-{n}"     gives   meeting-1.jpg  meeting-1.pdf
rem      --name "{pdf}-p{page}"   gives   report-p1.jpg  report-p1.pdf
rem    In the interactive window type  --name meeting-{n}  on its own line,
rem    every file dropped afterwards uses that template;  --name  alone
rem    restores the default 1, 2, 3 ...
rem  Requirements
rem    Python 3 (a bundled runtime is reused when one is found), plus
rem    pillow and numpy - they are installed automatically on first run.
rem  Note for editors
rem    Keep every cmd.exe line in this file pure ASCII and keep the line
rem    endings CRLF. All Chinese text of the user interface is printed by the
rem    embedded Python program at the bottom of this file, because cmd.exe
rem    mis-decodes UTF-8 batch lines on some systems (that is also what makes
rem    a double click window flash and vanish). Only edit the Python part when
rem    you want to change wording in Chinese.
rem  License: free to use and modify, keep the author line.
rem ===========================================================================

set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"
set "SELF=%~f0"
set "PDFBAT_SELF=%SELF%"
set "TMPPY=%TEMP%\pdf_split_%RANDOM%%RANDOM%.py"
set "TMPLIST=%TEMP%\pdf_split_%RANDOM%%RANDOM%.lst"
set "PDFBAT_PY=%TMPPY%"
set "RC=0"
set "CWD_DONE="

if /i "%~1"=="-h" goto :usage
if /i "%~1"=="--help" goto :usage
if /i "%~1"=="/?" goto :usage
if /i "%~1"=="-v" goto :usage
if /i "%~1"=="--version" goto :usage

rem ---- 1. find a Python 3 that really runs ----------------------------------
rem  A bare python.exe can be the Microsoft Store stub: it exits at once and
rem  the window disappears. So every candidate has to prove itself with
rem  -c "import sys" before it is accepted.
set "PY="
if exist "%~dp0python\python.exe" (
    "%~dp0python\python.exe" -c "import sys" >nul 2>nul
    if not errorlevel 1 set "PY="%~dp0python\python.exe""
)
if not defined PY if exist "C:\Users\DELL\.dsh\dsh-runtimes\dsh-next-primary-runtime\dependencies\python\python.exe" (
    "C:\Users\DELL\.dsh\dsh-runtimes\dsh-next-primary-runtime\dependencies\python\python.exe" -c "import sys" >nul 2>nul
    if not errorlevel 1 set "PY="C:\Users\DELL\.dsh\dsh-runtimes\dsh-next-primary-runtime\dependencies\python\python.exe""
)
if not defined PY (
    where python >nul 2>nul
    if not errorlevel 1 (
        python -c "import sys" >nul 2>nul
        if not errorlevel 1 set "PY=python"
    )
)
if not defined PY (
    py -3 -c "import sys" >nul 2>nul
    if not errorlevel 1 set "PY=py -3"
)
if not defined PY goto :no_python

rem ---- 2. make sure pillow and numpy are there -------------------------------
%PY% -c "import PIL, numpy" >nul 2>nul
if errorlevel 1 (
    echo [SETUP] installing pillow and numpy, the first run takes a moment ...
    %PY% -m pip install --quiet --disable-pip-version-check pillow numpy
    %PY% -c "import PIL, numpy" >nul 2>nul
    if errorlevel 1 goto :no_deps
)

rem ---- 3. unpack the embedded python program ---------------------------------
set "EXTRACT_OK="
set "EXTRACT_CMD=$s=[IO.File]::ReadAllLines($env:PDFBAT_SELF,[Text.Encoding]::UTF8);$a=[Array]::IndexOf($s,'::#>>>PY');$b=[Array]::IndexOf($s,'::#<<<PY');if($a -lt 0 -or $b -le $a){exit 1};$n=$b-$a-1;$o=New-Object string[] $n;[Array]::Copy($s,$a+1,$o,0,$n);[IO.File]::WriteAllLines($env:PDFBAT_PY,$o,(New-Object Text.UTF8Encoding($false)))"
where powershell >nul 2>nul
if not errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "%EXTRACT_CMD%" >nul 2>nul
    if exist "%TMPPY%" set "EXTRACT_OK=1"
)
if not defined EXTRACT_OK (
    where pwsh >nul 2>nul
    if not errorlevel 1 (
        pwsh -NoProfile -Command "%EXTRACT_CMD%" >nul 2>nul
        if exist "%TMPPY%" set "EXTRACT_OK=1"
    )
)
if not defined EXTRACT_OK goto :no_unpack

rem ---- 4. arguments came from dropping files onto the icon -------------------
if "%~1"=="" goto :home

:run_args
%PY% "%TMPPY%" %*
set "RC=%ERRORLEVEL%"
echo "%*" | findstr /i /c:"-nopause" >nul
if not errorlevel 1 goto :cleanup

rem ---- 5. home menu: 1 = split, 2 = compress --------------------------------
set "MODEOPT="
:home
%PY% "%TMPPY%" --home
set "PICK="
set /p "PICK="
if "%PICK%"=="1" goto :mode_split
if "%PICK%"=="2" goto :mode_compress
if "%PICK%"=="3" goto :mode_watermark
if "%PICK%"=="4" goto :mode_rename
if "%PICK%"=="5" goto :mode_office
if "%PICK%"=="0" goto :cleanup
if /i "%PICK%"=="q" goto :cleanup
if not defined PICK goto :home_retry
echo [i] please type 1-5, or 0 / q to quit
goto :home

:home_retry
echo   [i] please type 1-5, or 0 / q to quit
goto :home

:mode_split
set "MODEOPT="
%PY% "%TMPPY%" --menu
goto :ask

:mode_compress
%PY% "%TMPPY%" --compress-menu
set "TARGET="
set /p "TARGET="
if "%TARGET%"=="0" goto :home
if not defined TARGET goto :cz_auto
echo.%TARGET%| findstr /r /c:"^[0-9][0-9.]*$" >nul
if errorlevel 1 (
    echo [i] please type a number in MB, for example 5
    goto :mode_compress
)
goto :cz_go
:cz_auto
set "TARGET=auto"
:cz_go
set "MODEOPT=--compress --target %TARGET%"
%PY% "%TMPPY%" --compress-ready "%TARGET%"
goto :ask

:mode_watermark
set "MODEOPT="
%PY% "%TMPPY%" --wm-menu

:ask_wm
echo.
set "LINE="
set /p "LINE=PDF: "
if not defined LINE goto :ask_wm
set "L2=%LINE:"=%"
if /i "%L2%"=="q" goto :cleanup
if "%L2%"=="0" goto :home
%PY% "%TMPPY%" --scan-watermark --open-preview %LINE%
if errorlevel 1 goto :ask_wm
%PY% "%TMPPY%" --wm-confirm
set "YES="
set /p "YES="
if /i not "%YES%"=="y" goto :ask_wm
%PY% "%TMPPY%" --remove-watermark %LINE%
echo.
goto :ask_wm

rem ---- 6. interactive loop: the window never closes by itself ----------------
:ask
echo.
set "LINE="
set /p "LINE=PDF: "
if not defined LINE goto :ask_empty
rem  strip the quotes first: a dropped path may contain () or & and comparing
rem  ""C:\a (2)\b.pdf""=="0" would be a cmd syntax error and kill the window
set "L2=%LINE:"=%"
if /i "%L2%"=="q" goto :cleanup
if /i "%L2%"=="quit" goto :cleanup
if /i "%L2%"=="exit" goto :cleanup
if "%L2%"=="0" goto :home
if "%L2%"=="." goto :run_here
if /i "%L2%"=="n" if "%MODEOPT%"=="" goto :namewiz

rem  The dropped path goes through a manifest file, so & ^ ( ) and spaces in
rem  a path can not break the command line. A line that only carries options
rem  (for example  --name meeting-{n}  ) is handled by the python side, which
rem  remembers the template for the following drops.
>"%TMPLIST%" echo(%LINE%
%PY% "%TMPPY%" --interactive %MODEOPT% --from-list "%TMPLIST%"
set "RC=%ERRORLEVEL%"
goto :ask

:ask_empty
if defined CWD_DONE goto :home
set "CWD_DONE=1"

:run_here
%PY% "%TMPPY%" --interactive %MODEOPT% "%~dp0."
set "RC=%ERRORLEVEL%"
goto :ask

:mode_rename
%PY% "%TMPPY%" --rename-menu
set "RM="
set /p "RM="
if not defined RM goto :mode_rename
set "RM2=%RM:"=%"
if "%RM2%"=="0" goto :home
if /i "%RM2%"=="q" goto :cleanup
if /i "%RM2%"=="z" goto :rename_undo
if /i "%RM2%"=="t" goto :rename_tpl
if /i "%RM2%"=="o" goto :rename_order
if /i "%RM2%"=="p" goto :rename_preview
if /i "%RM2%"=="y" goto :rename_apply
rem  any other input is treated as a path to scan.
rem  the path is passed straight through as an argument - writing it into a
rem  manifest with echo would break on & ( ) and other characters in file names.
%PY% "%TMPPY%" --rename-scan %RM%
if errorlevel 1 (
    echo.
    echo   [i] scan failed - check the path, quote it if it contains spaces
    set "PAUSE1="
    set /p "PAUSE1=  press Enter to continue ... "
)
echo.
goto :mode_rename

:rename_preview
%PY% "%TMPPY%" --rename-show
echo.
goto :mode_rename

:rename_undo
%PY% "%TMPPY%" --rename-undo
echo.
goto :mode_rename

:rename_apply
%PY% "%TMPPY%" --rename-apply
echo.
goto :mode_rename

:rename_order
%PY% "%TMPPY%" --rename-order-prompt
set "OD="
set /p "OD="
if not defined OD goto :mode_rename
%PY% "%TMPPY%" --rename-order "%OD%"
echo.
goto :mode_rename

:rename_tpl
%PY% "%TMPPY%" --rename-template-menu
set "TC="
set /p "TC="
if "%TC%"=="0" goto :mode_rename
if "%TC%"=="1" goto :rt_prefix_a
if "%TC%"=="2" goto :rt_prefix_b
if "%TC%"=="3" goto :rt_tpl
goto :mode_rename

:rt_prefix_a
%PY% "%TMPPY%" --rename-prefix-prompt
set "PFX="
set /p "PFX="
>"%TMPLIST%" echo(%PFX%
%PY% "%TMPPY%" --rename-mode A --rename-prefix-from "%TMPLIST%"
echo.
goto :mode_rename

:rt_prefix_b
%PY% "%TMPPY%" --rename-prefix-prompt
set "PFX="
set /p "PFX="
>"%TMPLIST%" echo(%PFX%
%PY% "%TMPPY%" --rename-mode B --rename-prefix-from "%TMPLIST%"
echo.
goto :mode_rename

:rt_tpl
%PY% "%TMPPY%" --rename-tpl-prompt
set "TPL="
set /p "TPL="
>"%TMPLIST%" echo(%TPL%
%PY% "%TMPPY%" --rename-mode C --rename-tpl-from "%TMPLIST%"
echo.
goto :mode_rename

:mode_office
set "OAPP="
:office_menu
%PY% "%TMPPY%" --office-menu
set "OA="
set /p "OA="
if "%OA%"=="0" goto :home
if /i "%OA%"=="q" goto :cleanup
if "%OA%"=="1" set "OAPP=word"
if "%OA%"=="2" set "OAPP=excel"
if "%OA%"=="3" set "OAPP=ppt"
if not defined OAPP goto :office_menu
goto :office_list

:office_list
%PY% "%TMPPY%" --office-list %OAPP%
set "ON="
set /p "ON="
if not defined ON goto :office_list
if "%ON%"=="0" goto :mode_office
if /i "%ON%"=="q" goto :cleanup
echo %ON%| findstr /r /c:"^[0-9][0-9]*$" >nul
if errorlevel 1 goto :office_list
%PY% "%TMPPY%" --office-tip %OAPP% %ON%
echo.
goto :office_list

rem  name wizard: the chinese text is printed by the embedded python, cmd only
rem  reads the choice, so this file can stay pure ascii.
:namewiz
%PY% "%TMPPY%" --name-menu
set "CH="
set /p "CH="
if "%CH%"=="1" goto :nz_default
if "%CH%"=="2" goto :nz_pdfname
if "%CH%"=="3" goto :nz_custom
if "%CH%"=="0" goto :ask
if not defined CH goto :ask
echo [i] please type 1, 2, 3, 4, 5 or 0
goto :namewiz

:nz_default
%PY% "%TMPPY%" --set-name ""
goto :ask

:nz_pdfname
%PY% "%TMPPY%" --set-name "{pdf}-{n}"
goto :ask

:nz_custom
%PY% "%TMPPY%" --name-prompt
set "NM="
set /p "NM="
if not defined NM goto :ask
>"%TMPLIST%" echo(%NM%
%PY% "%TMPPY%" --set-name-from "%TMPLIST%"
goto :ask

rem ---- tail -----------------------------------------------------------------
:usage
echo.
echo   PDF page splitter v2.4   -   XiaoNanSanSui (xiaonansansui)
echo   GitHub: https://github.com/xiaonansansui
echo.
echo   usage:
echo     this.bat "file_or_folder" [-o outdir] [--name template]
echo              [--open^|--no-open] [-nopause]
echo     this.bat --compress [--target MB] "file_or_folder"
echo     this.bat             (interactive: 1 = split, 2 = compress)
echo   output:
echo     OUT_DIR\pdf name\1.jpg 1.pdf 2.jpg 2.pdf ...
echo   name template placeholders:
echo     {n} {nn} {page} {pdf} {date}
echo     example: --name "meeting-{n}"  =^>  meeting-1.jpg  meeting-1.pdf
echo     no placeholder at all -^> duplicates get a -2, -3 suffix
endlocal & exit /b 0

:no_python
echo.
echo   [ERROR] no usable Python 3 found.
echo           install Python 3 and tick "Add python.exe to PATH":
echo             https://www.python.org/downloads/
echo           or drop a portable python.exe into a  python\  folder next to
echo           this file.
set "RC=1"
goto :hold

:no_deps
echo.
echo   [ERROR] pillow / numpy could not be installed. run this by hand:
echo             %PY% -m pip install pillow numpy
set "RC=1"
goto :hold

:no_unpack
echo.
echo   [ERROR] could not read the embedded Python program out of this file.
echo           keep this file saved as UTF-8 with CRLF line endings, and do
echo           not remove the PY-BEGIN / PY-END marker lines.
set "RC=1"
goto :hold

:hold
echo.
set "ANYKEY="
set /p "ANYKEY=press Enter to close this window ... "
endlocal & exit /b %RC%

:cleanup
%PY% "%TMPPY%" --bye 2>nul
del /f /q "%TMPPY%" >nul 2>nul
del /f /q "%TMPLIST%" >nul 2>nul
endlocal & exit /b %RC%

::#>>>PY
# -*- coding: utf-8 -*-
"""拆分PDF图片 —— 把 PDF 里每页的大图拆出来，存成 N组.jpg，并生成同名 A4 PDF。

作者   : 小楠三岁
GitHub : https://github.com/xiaonansansui
版本   : 2.7

用法:
    python 拆分PDF图片.py [PDF或文件夹 ...] [-o 输出目录] [--name 模板]
                           [--jpg-only] [--pdf-only]
    python 拆分PDF图片.py --from-list 清单.txt
不带参数时处理当前目录（含子目录）里的所有 PDF。

输出文件名可以用 --name 自定义，例如 --name "会议纪要-{n}" 会得到
会议纪要-1.jpg / 会议纪要-1.pdf …… 占位符见 --help。
"""
import hashlib
import io
import json
import os
import re
import shlex
import sys
import tempfile
import unicodedata
import zlib
import time
from collections import Counter

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print('缺少依赖，请先执行:  pip install pillow numpy')
    raise SystemExit(2)

TITLE = '拆分PDF图片'
__author__ = '小楠三岁'
__github__ = 'https://github.com/xiaonansansui'
__version__ = '2.7'

OUT_ROOT_NAME = '拆分图片'
A4_SHORT, A4_LONG = 595.28, 841.89   # A4 短边/长边（pt）
MARGIN = 14.0

MENU_TEXT = '''
  ================================================================
   拆分PDF图片 v2.2    ·    作者: 小楠三岁    ·    @xiaonansansui
  ================================================================
   把 PDF 文件（或文件夹）直接拖进这个窗口，然后回车
   可以一次拖多个；直接回车 = 处理本程序所在目录
   处理完会问要不要打开保存目录（回车 = 不打开）
   输入 q 回车 = 退出     （窗口不会自己关，拖文件也不会关）
   输入 0 回车 = 回到上一层菜单
  ----------------------------------------------------------------
   想把输出文件改成自己起的名字：输入 n 回车，按提示选就行
  ================================================================
'''

NAME_MENU = '''
  ---------------------------------------------------------------
   输出文件名想怎么起？（以后拖进来的文件都用这个）
     1  默认              1组、2组、3组 ……
     2  用 PDF 的名字      会议纪要-1、会议纪要-2 ……   （推荐）
     3  自己起一个名字    比如输入“周例会”→“周例会-1”“周例会-2”
     0  不改，直接返回
  ---------------------------------------------------------------
   请输入 1 / 2 / 3（0 返回）: '''

NAME_PROMPT = '''
   请输入名字（例如 周例会），直接回车 = 取消: '''

HOME_TEXT = '''
  ================================================================
   拆分PDF图片 v2.4    ·    作者: 小楠三岁    ·    @xiaonansansui
  ================================================================
     1   拆分 PDF      每页的大图拆成 jpg，并生成同名 A4 PDF
     2   压缩 PDF      把 PDF 压到你要的大小（比如 5 MB）
     3   去水印        删掉每页重复的图片水印（如扫描全能王 logo），正文不动
     0   退出
  ================================================================
   请选择 1 / 2 / 3（输入 0 退出）: '''

WM_MENU = '''
  ---------------------------------------------------------------
   去水印：先把 PDF 拖进来，程序会扫一遍，找出“每页都贴的同一张图”
   （扫描全能王、某某扫描 App 的 logo 就是这种）
   预览图：左边是页面、红框标出位置，右边是水印本身
   确认后直接在 PDF 结构里删掉它，正文图片和文字一个像素都不动
   输出：原名_去水印.pdf（原文件不动）
  ---------------------------------------------------------------
   把 PDF 拖进这个窗口，然后回车（输入 0 返回上一层）
'''

WM_CONFIRM = '''
  ---------------------------------------------------------------
   右边这张图就是它找到的水印，确定要去掉它吗？
   （y = 去掉   n 或直接回车 = 不去）
  ---------------------------------------------------------------
   确认（y/n）: '''

COMP_MENU = '''
  ---------------------------------------------------------------
   压缩体积：把 PDF 压到你要的大小（单位 MB，1 MB = 1024 KB）
     · 直接回车    = 自动压缩（质量 75，长边 2480 像素，推荐）
     · 输入数字    = 尽量压到这个大小，例如 5
     · 输入 0 回车 = 返回上一层
  ---------------------------------------------------------------
   目标大小（MB）: '''

COMP_READY = '''
  ---------------------------------------------------------------
   好的，目标大小：%s
   把 PDF 文件（或文件夹）拖进这个窗口，然后回车
   压出来的文件放在原 PDF 旁边，叫「原名_压缩.pdf」
  ---------------------------------------------------------------
'''

NAME_HELP = '''
输出文件名模板（--name）可用的占位符：

  {n}      图片序号，从 1 开始          -> 1, 2, 3 ...
  {nn}     序号补零到两位                -> 01, 02, 03 ...
  {page}   图片在原 PDF 里的页码          -> 1, 2, 3 ...
  {pdf}    原 PDF 的文件名（不含扩展名）
  {date}   今天的日期                    -> 20261124

例子：
  --name "{n}"               -> 1.jpg  1.pdf  2.jpg  2.pdf
  --name "{n}组"             -> 1组.jpg  1组.pdf（默认）
  --name "会议纪要-{n}"       -> 会议纪要-1.jpg  会议纪要-1.pdf
  --name "{pdf}-第{page}页"   -> 构溪社区第一组会议纪要-第1页.jpg

文件名里不能用的字符（\\ / : * ? " < > |）会自动换成下划线；
模板里没有 {n}/{page} 这类唯一占位符时，重名的会自动加 -2、-3 后缀。
'''

BYE_TEXT = '  再见  ·  小楠三岁  ·  GitHub @xiaonansansui'

END_HINT = ('  ---- 小楠三岁  ·  @xiaonansansui  ----  '
            '继续把 PDF 拖进窗口回车；q 退出')


def banner():
    print('%s v%s   ·   作者: %s   ·   GitHub: %s'
          % (TITLE, __version__, __author__, __github__))


# ---------- 终端美化：框线 + 颜色 ----------

def _enable_ansi():
    try:
        import ctypes
        k = ctypes.windll.kernel32
        h = k.GetStdHandle(-11)
        mode = ctypes.c_uint32()
        if not k.GetConsoleMode(h, ctypes.byref(mode)):
            return False
        return bool(k.SetConsoleMode(h, mode.value | 0x0004))
    except Exception:
        return False


ANSI = _enable_ansi()
BOX_W = 62


def paint(text, code):
    if not ANSI or not code:
        return text
    return '\x1b[%sm%s\x1b[0m' % (code, text)


def _dw(s):
    """显示宽度：中日韩全角算 2 列，ANSI 转义不算宽度。"""
    s = re.sub(r'\x1b\[[0-9;]*m', '', s)
    w = 0
    for ch in s:
        if unicodedata.combining(ch):
            continue
        w += 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
    return w


def _pad(s, width):
    return s + ' ' * max(0, width - _dw(s))


def _box(rows, width=BOX_W, edge='36'):
    out = [paint('┌' + '─' * width + '┐', edge)]
    for r in rows:
        out.append(paint('│', edge) + ' ' + _pad(r, width - 2) + ' ' + paint('│', edge))
    out.append(paint('└' + '─' * width + '┘', edge))
    return '\n'.join(out)


def _rule(width=BOX_W):
    return '  ' + paint('─' * width, '90')


def print_home():
    print()
    tpl = load_name_template()
    rows = [
        '',
        '  ' + paint('拆分PDF图片', '1;36') + paint('  v%s' % __version__, '90')
        + '          ' + paint('小楠三岁 · @xiaonansansui', '90'),
        '  ' + paint('拆图 / 压小 / 去水印 / 批量改名 / 办公疑难速查', '90'),
        '',
        '   ' + paint('[1]', '1;33') + '   拆分 PDF'
        + '     每页大图 → N组.jpg + 同名 A4 PDF',
        '   ' + paint('[2]', '1;33') + '   压缩 PDF'
        + '     压到指定大小（比如 5 MB）',
        '   ' + paint('[3]', '1;33') + '   去水印'
        + '       删掉每页重复的图片水印（扫描软件加的）',
        '   ' + paint('[4]', '1;33') + '   批量改名'
        + '     按模板统一改名（先排顺序，预览后再执行）',
        '   ' + paint('[5]', '1;33') + '   办公疑难杂症'
        + '  Word/Excel/PPT 常见坑',
        '',
        '   ' + paint('当前文件名：', '90') + describe_template(tpl),
        '',
    ]
    print(_box(rows))
    print('  ' + paint('请输入 1 / 2 / 3 / 4 / 5', '1') + paint('（0 或 q 退出）', '90')
          + paint(' : ', '1'), end='')


def print_split_menu():
    print()
    rows = [
        '',
        '  ' + paint('① 拆分 PDF', '1;36') + paint('   —   每页大图拆成 jpg，并生成同名 A4 PDF', '90'),
        '',
        '   把 PDF 文件（或文件夹）拖进窗口，回车开始',
        '   可以一次拖多个  ·  直接回车 = 处理本程序所在目录',
        '   处理完会问要不要打开保存目录（回车 = 不打开）',
        '',
        '   ' + paint('n', '1;33') + ' 改输出文件名    '
        + paint('0', '1;33') + ' 回主界面    ' + paint('q', '1;33') + ' 退出',
        '',
        '   当前文件名：' + describe_template(load_name_template()),
        '',
    ]
    print(_box(rows))


def print_comp_menu():
    print()
    rows = [
        '',
        '  ' + paint('② 压缩 PDF', '1;36') + paint('   —   把 PDF 压到你要的大小（单位 MB）', '90'),
        '',
        '   ' + paint('直接回车', '1;33') + '  = 自动压缩（质量 75，长边 2480 像素，推荐）',
        '   ' + paint('输入数字', '1;33') + '  = 尽量压到这个大小，例如 5',
        '   ' + paint('0', '1;33') + ' 回车     = 返回主界面',
        '',
    ]
    print(_box(rows))
    print('  ' + paint('目标大小（MB）: ', '1'), end='')


def print_wm_menu():
    print()
    rows = [
        '',
        '  ' + paint('③ 去水印', '1;36') + paint('   —   删掉“每页都贴的同一张图”', '90'),
        '',
        '   扫描全能王、某某扫描 App 的 logo 就属于这种',
        '   流程：先扫描 → 出预览图 → 你确认 → 才动手',
        '   预览图左边是页面（红框标位置），右边是水印本身',
        '   删的是 PDF 里的一条绘制指令，正文图片和文字一个像素都不动',
        '   输出：原名_去水印.pdf（原文件不动）',
        '',
        '   ' + paint('0', '1;33') + ' 回主界面    ' + paint('q', '1;33') + ' 退出',
        '',
    ]
    print(_box(rows))


def print_wm_confirm():
    print()
    rows = [
        '',
        '  右边这张图就是它找到的水印，确定要去掉它吗？',
        '  ' + paint('y', '1;33') + ' 去掉        '
        + paint('n 或回车', '1;33') + ' 不去         '
        + paint('0', '1;33') + ' 回主界面',
        '',
    ]
    print(_box(rows))
    print('  ' + paint('确认（y/n）: ', '1'), end='')


def print_after_task():
    """每次任务结束后的选项提示。"""
    print()
    print(_rule())
    print('   ' + paint('回车', '1;33') + ' 继续处理下一个      '
          + paint('0', '1;33') + ' 回主界面      '
          + paint('q', '1;33') + ' 退出')
    print(_rule())


# ---------- ④ 批量改名 ----------

RENAME_STATE = os.path.join(tempfile.gettempdir(), 'pdfsplit_rename.json')
RENAME_LOG_DIR = os.path.join(tempfile.gettempdir(), 'pdfsplit_undo')


def _rename_load():
    try:
        with open(RENAME_STATE, 'r', encoding='utf-8') as fh:
            return json.load(fh)
    except Exception:
        return None


def _rename_save(st):
    try:
        with open(RENAME_STATE, 'w', encoding='utf-8') as fh:
            json.dump(st, fh, ensure_ascii=False)
    except Exception:
        pass


def _exif_time(path):
    try:
        im = Image.open(path)
        ex = im.getexif()
        v = ex.get(36867) or ex.get(306)
        if v:
            return time.mktime(time.strptime(str(v)[:19], '%Y:%m:%d %H:%M:%S'))
    except Exception:
        pass
    try:
        im = Image.open(path)
        for tag in (36867, 306):
            v = im._getexif().get(tag) if hasattr(im, '_getexif') else None
            if v:
                return time.mktime(time.strptime(str(v)[:19], '%Y:%m:%d %H:%M:%S'))
    except Exception:
        pass
    return None


def _name_date(stem):
    m = re.search(r'(20\d{2})\s*[-_.年/]?\s*(\d{1,2})\s*[-_.月/]?\s*(\d{1,2})'
                  r'(?:[ T._]+(\d{1,2})[.:：时_](\d{1,2}))?', stem)
    if not m:
        return None
    try:
        hh = int(m.group(4)) if m.group(4) else 0
        mm = int(m.group(5)) if m.group(5) else 0
        return time.mktime((int(m.group(1)), int(m.group(2)), int(m.group(3)), hh, mm, 0, 0, 0, -1))
    except Exception:
        return None


def _name_seq(stem):
    for pat in (r'第\s*(\d{1,3})\s*[页張张]', r'(?:^|[_\-\s])(\d{1,4})(?=$|[_\-\s])',
                r'[（(](\d{1,3})[）)]'):
        m = re.search(pat, stem)
        if m:
            try:
                return int(m.group(1))
            except Exception:
                pass
    return None


def _collect_files(paths, recurse=False):
    out = []
    for p in paths:
        p = os.path.abspath(p)
        if os.path.isdir(p):
            walk = os.walk(p) if recurse else [(p, [], os.listdir(p))]
            for dirpath, dirs, files in walk:
                dirs[:] = [d for d in dirs if not d.startswith('.')]
                for f in files:
                    if f.startswith('.') or f == '_改名顺序_联系表.png':
                        continue
                    out.append(os.path.join(dirpath, f))
        elif os.path.isfile(p):
            out.append(p)
    return out


def _scan_items(files):
    items = []
    for f in files:
        stem, ext = os.path.splitext(os.path.basename(f))
        try:
            mt = os.path.getmtime(f)
        except Exception:
            continue
        t, src = _name_date(stem), '原名日期'
        if t is None:
            t = _exif_time(f)
            src = 'EXIF' if t else None
        if t is None:
            t, src = mt, '修改时间'
        items.append(dict(path=f, dir=os.path.dirname(f), stem=stem, ext=ext.lower(),
                          mtime=mt, t=t, src=src, seq=_name_seq(stem)))
    return items


def _sort_items(items):
    """有页码/序号的优先按序号排，否则按时间；都用名字兜底。"""
    withseq = [i for i in items if i['seq'] is not None]
    if len(withseq) >= max(2, int(len(items) * 0.8)):
        items.sort(key=lambda i: (i['seq'] if i['seq'] is not None else 10 ** 6,
                                  i['stem']))
        return '名字里的序号/页码'
    items.sort(key=lambda i: (i['t'], i['stem']))
    return '时间（原名日期 → EXIF → 修改时间）'


def _contact_sheet(items, out_png, limit=24):
    cols, cell = 5, 240
    rows = (min(len(items), limit) + cols - 1) // cols
    if rows == 0:
        return None
    pad, head = 26, 26
    sheet = Image.new('RGB', (cols * cell, rows * (cell + head) + pad), 'white')
    from PIL import ImageDraw
    dr = ImageDraw.Draw(sheet)
    for idx, it in enumerate(items[:limit]):
        r, c = divmod(idx, cols)
        x0, y0 = c * cell, r * (cell + head) + pad
        dr.rectangle([x0 + 4, y0 + 4, x0 + cell - 4, y0 + cell + head - 4], outline='#cccccc')
        dr.text((x0 + 8, y0 + 6), '#%02d  %s' % (idx + 1, it['ext'] or 'dir'),
                fill='#333333')
        try:
            if it['ext'] in ('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp', '.tif', '.tiff'):
                im = Image.open(it['path'])
                im.thumbnail((cell - 16, cell - 16))
                sheet.paste(im.convert('RGB'),
                            (x0 + (cell - im.width) // 2, y0 + head + (cell - im.height) // 2))
            else:
                dr.text((x0 + 12, y0 + head + 90), os.path.basename(it['path'])[:26],
                        fill='#666666')
        except Exception:
            dr.text((x0 + 12, y0 + head + 90), '（无法预览）', fill='#999999')
        dr.text((x0 + 8, y0 + cell + head - 4),
                os.path.basename(it['path'])[:30], fill='#000000')
    sheet.save(out_png)
    return out_png


def _sanitize(name):
    name = re.sub(r'[\\/:*?"<>|\r\n\t]', '-', name)
    name = re.sub(r'\s+', ' ', name).strip(' .')
    return name[:150] or 'file'


def _render_name(it, idx, mode, prefix, tpl):
    if mode == 'A':
        base = '%s%02d' % (prefix, idx)
    elif mode == 'B':
        base = '%s%s' % (prefix, it['stem'])
    elif mode == 'C':
        base = (tpl or '')
        base = base.replace('{nnn}', '%03d' % idx).replace('{nn}', '%02d' % idx)
        base = base.replace('{n}', str(idx)).replace('{原名}', it['stem'])
        base = base.replace('{ext}', it['ext'].lstrip('.'))
        base = base.replace('{日期}', time.strftime('%Y%m%d', time.localtime(it['t'])))
        base = base.replace('{prefix}', prefix)
    else:
        base = it['stem']
    return _sanitize(base)


def _plan(st):
    items = [st['items'][i] for i in st['order']]
    used, plan = set(), []
    seen, n = {}, 0
    for it in items:
        key = it['stem'].lower()
        if key in seen:
            idx = seen[key]
        else:
            n += 1
            idx = n
            seen[key] = idx
        base = _render_name(it, idx, st['mode'], st['prefix'], st['tpl'])
        name, k = base + it['ext'], 2
        while name.lower() in used:
            name = '%s-%d%s' % (base, k, it['ext'])
            k += 1
        used.add(name.lower())
        plan.append((it, os.path.join(it['dir'], name)))
    return plan


def rename_scan(paths, recurse=False, say=print):
    files = _collect_files(paths, recurse)
    if not files:
        say('   没有扫到文件。把文件夹或文件拖进来再回车。')
        return None
    items = _scan_items(files)
    by = _sort_items(items)
    st = dict(items=items, order=list(range(len(items))), mode='B', prefix='', tpl='',
              root=os.path.dirname(items[0]['path']) if items else '')
    _rename_save(st)
    say('   共 %d 个文件' % len(items))
    kinds = {}
    for it in items:
        kinds[it['ext'] or '(无扩展名)'] = kinds.get(it['ext'] or '(无扩展名)', 0) + 1
    say('   类型：' + '  '.join('%s×%d' % (k, v) for k, v in sorted(kinds.items())))
    srcs = {}
    for it in items:
        srcs[it['src']] = srcs.get(it['src'], 0) + 1
    say('   时间依据：' + '  '.join('%s×%d' % (k, v) for k, v in sorted(srcs.items())))
    say('   排序依据：%s' % by)
    png = _contact_sheet(items, os.path.join(tempfile.gettempdir(), '改名联系表.png'))
    if png:
        say('   联系表：%s' % os.path.basename(png))
        try:
            os.startfile(png)
        except Exception:
            pass
    return st


def rename_show(st, page=1, per=12, say=print):
    plan = _plan(st)
    total = len(plan)
    pages = max(1, (total + per - 1) // per)
    page = max(1, min(page, pages))
    rows = ['', '  ' + paint('改名预览', '1;36') + paint('   第 %d/%d 页   共 %d 个' % (page, pages, total), '90'), '']
    for i in range((page - 1) * per, min(page * per, total)):
        it, newp = plan[i]
        rows.append('   %02d  %s' % (i + 1, os.path.basename(it['path'])))
        rows.append('     ' + paint('→', '32') + '  ' + os.path.basename(newp))
    rows.append('')
    rows.append('  ' + paint('模板：', '90') + _mode_text(st))
    rows.append('')
    print(_box(rows))


def _mode_text(st):
    if st['mode'] == 'A':
        return '前缀 + 两位序号  →  %s01%s' % (st['prefix'] or '', st['items'][0]['ext'] if st['items'] else '')
    if st['mode'] == 'B':
        return '前缀 + 原名      →  %s原名%s' % (st['prefix'] or '', st['items'][0]['ext'] if st['items'] else '')
    if st['mode'] == 'C':
        return '自定义模板：%s' % st['tpl']
    return '（未设置）'


def rename_apply(st, say=print):
    plan = _plan(st)
    os.makedirs(RENAME_LOG_DIR, exist_ok=True)
    log_path = os.path.join(RENAME_LOG_DIR, 'undo_%s.txt' % time.strftime('%Y%m%d_%H%M%S'))
    done, skip = [], []
    for it, newp in plan:
        old = it['path']
        if os.path.abspath(old) == os.path.abspath(newp):
            continue
        if os.path.exists(newp) and os.path.abspath(newp) != os.path.abspath(old):
            skip.append((old, '目标已存在'))
            continue
        try:
            if os.path.abspath(old).lower() == os.path.abspath(newp).lower():
                tmp = old + '.renaming'
                os.rename(old, tmp)
                os.rename(tmp, newp)
            else:
                os.rename(old, newp)
            done.append((old, newp))
        except Exception as exc:
            skip.append((old, str(exc)))
    with open(log_path, 'w', encoding='utf-8') as fh:
        for old, new in done:
            fh.write('%s\t%s\n' % (old, new))
    say('   已改名 %d 个' % len(done))
    if skip:
        say('   跳过 %d 个：' % len(skip))
        for old, why in skip[:5]:
            say('     · %s（%s）' % (os.path.basename(old), why))
        if len(skip) > 5:
            say('     · ……还有 %d 个' % (len(skip) - 5))
    say('   撤销记录：%s' % os.path.basename(log_path))
    return len(done)


def rename_undo(say=print):
    if not os.path.isdir(RENAME_LOG_DIR):
        say('   没有可撤销的记录。')
        return 0
    logs = sorted(os.listdir(RENAME_LOG_DIR))
    if not logs:
        say('   没有可撤销的记录。')
        return 0
    latest = os.path.join(RENAME_LOG_DIR, logs[-1])
    n = 0
    with open(latest, 'r', encoding='utf-8') as fh:
        for line in fh:
            parts = line.rstrip('\n').split('\t')
            if len(parts) != 2:
                continue
            old, new = parts
            try:
                if os.path.exists(new) and not os.path.exists(old):
                    os.rename(new, old)
                    n += 1
            except Exception:
                pass
    os.remove(latest)
    say('   已撤销 %d 个改名（记录：%s）' % (n, os.path.basename(latest)))
    return n


def rename_menu():
    st = _rename_load()
    rows = ['', '  ' + paint('④ 批量改名', '1;36')
            + paint('   —   先排好顺序，再套模板统一改名', '90'), '']
    if st and st.get('items'):
        rows += ['   已扫描：%d 个文件' % len(st['items']),
                 '   ' + paint('模板：', '90') + _mode_text(st), '']
        rows += ['   ' + paint('t', '1;33') + ' 设模板      '
                 + paint('o', '1;33') + ' 调顺序      '
                 + paint('p', '1;33') + ' 预览']
        rows += ['   ' + paint('y', '1;33') + ' 执行改名    '
                 + paint('z', '1;33') + ' 撤销上一次  '
                 + paint('0', '1;33') + ' 回主界面', '']
    else:
        rows += ['   把文件夹（或一堆文件）拖进窗口，回车开始扫描', '']
        rows += ['   ' + paint('z', '1;33') + ' 撤销上一次改名    '
                 + paint('0', '1;33') + ' 回主界面', '']
    print(_box(rows))
    print('  ' + paint('输入命令或拖入路径', '1') + paint(' : ', '1'), end='')


def rename_template_menu():
    rows = ['', '  ' + paint('给这批文件起名', '1;36'), '',
            '   ' + paint('1', '1;33') + '  加前缀 + 两位序号     '
            + paint('例：构溪社区-1组-01.jpg', '90'),
            '   ' + paint('2', '1;33') + '  加前缀 + 保留原名     '
            + paint('例：构溪社区-1组-会议纪要.jpg', '90'),
            '   ' + paint('3', '1;33') + '  自己写模板            '
            + paint('{nn} {n} {原名} {日期} {ext}', '90'),
            '   ' + paint('0', '1;33') + '  取消', '']
    print(_box(rows))
    print('  ' + paint('请选择 1 / 2 / 3', '1') + paint(' : ', '1'), end='')


def rename_order_prompt():
    st = _rename_load()
    n = len(st['items']) if st else 0
    print('  ' + paint('按联系表输入新顺序（共 %d 个，例如 3 1 5 2）: ' % n, '1'), end='')
def rename_prefix_prompt():
    print('  ' + paint('请输入前缀（例如 构溪社区-1组-）: ', '1'), end='')


def rename_tpl_prompt():
    print('  ' + paint('请输入模板（占位符 {nn} {n} {原名} {日期} {ext}）: ', '1'), end='')


# ---------- ⑤ 办公软件疑难杂症（纯查询，不动文件） ----------

OFFICE_TIPS = [
    # ---------------- Word ----------------
    dict(app='word', title='表格跨页后表头不见了、一行被拦腰截成两页',
         why='Word 默认既不重复表头，也允许行内跨页断行',
         how=['选中表格第一行（表头）',
              '表格工具 → 布局 → 数据 → 勾选「重复标题行」',
              '选中整张表 → 右键「表格属性」→ 行 → 取消勾选「允许跨页断行」',
              '还想让单行完整落在一页：选中该行 → 段落 → 换行和分页 → 勾「段中不分页」'],
         note='表格属性里的“行”那一页才有“允许跨页断行”，别在“表格”页找'),
    dict(app='word', title='目录页码不对，更新后全乱',
         why='目录是“域”，正文改动后没更新；或标题没用统一的“标题1/2/3”样式',
         how=['点一下目录 → 按 F9（或右键 → 更新域）→ 选「更新整个目录」',
              '正文里的章标题必须用「开始 → 样式」里的 标题1/标题2，手改字号目录认不出',
              '页码全对但整体偏移：检查分节符，双击页码区确认“链接到前一节”状态'],
         note='打印前 F9 一次，目录就稳了'),
    dict(app='word', title='页眉下面那条横线删不掉',
         why='那不是画线，是“页眉”样式自带的段落下边框',
         how=['双击进入页眉区域',
              'Ctrl+A 选中页眉里的空段落',
              '开始 → 段落 → 边框按钮 → 选「无边框」',
              '还在：选中段落 → 段落对话框 → 边框和底纹 → 边框 → 无'],
         note='清掉段落边框就消失，别去删“形状”'),
    dict(app='word', title='自动编号变成黑方块、或者从 5 开始编',
         why='编号格式的字体缺失，或该段落的编号续接了上一段列表',
         how=['全选编号 → 右键「调整列表缩进」/「重新开始于 1」',
              '字体缺失：全选 → 把编号字体改成 宋体 或 微软雅黑',
              '彻底治：开始 → 多级列表 → 定义新的多级列表，绑定到标题样式'],
         note='复制别人文档最容易带进坏编号，粘贴时选「只保留文本」再套样式'),
    dict(app='word', title='同一份文档，别人电脑打开排版全乱',
         why='字体没嵌入，对方用了替代字体，行宽和分页全变',
         how=['交付一律另存为 PDF（文件 → 导出 → 创建 PDF）',
              '必须给 Word 源文件时：文件 → 选项 → 保存 → 勾「将字体嵌入文件」',
              '排版别用空格对齐，用制表符/表格/段落缩进'],
         note='正式材料：Word 里排好 → 导 PDF → 打印/上报都用 PDF'),
    dict(app='word', title='复制粘贴带进了原格式，整篇样式被搞乱',
         why='默认粘贴保留源格式',
         how=['粘贴后点右下角「粘贴选项」→ 选「只保留文本」',
              '一劳永逸：文件 → 选项 → 高级 → 剪切/复制/粘贴 → 默认粘贴方式改成「仅保留文本」',
              '已经乱了：Ctrl+A → 开始 → 样式 → 清除格式，再重新套用标题样式'],
         note='从网页/微信复制最脏，务必走“只保留文本”'),
    dict(app='word', title='页码从中间某页重新变成 1',
         why='那页前面插了“分节符（下一页）”，新节的页码默认续不上',
         how=['双击该页页脚 → 页眉页脚工具 → 页码 → 设置页码格式 → 选「续前节」',
              '想真正分节但不重置：取消该节页脚的「链接到前一节」再手动设起始页',
              '检查分节符：开始 → 显示/隐藏编辑标记（¶）'],
         note='看不到分节符，就是你按了 ¶ 按钮没开'),
    dict(app='word', title='图片到处乱跑，文字被压住',
         why='图片环绕方式默认是“嵌入型”以外的浮动方式',
         how=['点图片 → 布局选项 → 选「嵌入型」（最稳，跟着段落走）',
              '需要图文混排：选「四周型」并勾「锁定锚点」',
              '批量：选中图片 → 右键「大小和位置」→ 文字环绕 → 统一设置'],
         note='报告/公文类材料一律用嵌入型，不然一改字就全乱'),
    dict(app='word', title='空格删不掉，或者一排字怎么都对不齐',
         why='混进了全角空格、不间断空格（NBSP）或制表符',
         how=['开始 → 打开 ¶ 显示编辑标记，看空格到底是什么符号',
              '查找替换：Ctrl+H，查找框输入 ^s（不间断空格）替换为空',
              '全角空格：查找框粘贴一个全角空格，替换为空',
              '对齐别用空格：用制表符 + 标尺上的制表位'],
         note='公文里“首行缩进 2 字符”用段落设置，不要敲空格'),
    dict(app='word', title='表格列宽怎么拖都拖不动',
         why='开启了“根据窗口自动调整”，或单元格里有固定宽度/合并格',
         how=['表格工具 → 布局 → 自动调整 → 选「固定列宽」再拖',
              '右键表格属性 → 列 → 取消「指定宽度」的继承值后重新设',
              '整表拖不动：选中表格 → 右键 → 自动调整 → 根据内容/窗口切换一次'],
         note='先关掉“自动调整”，再拖边框'),
    dict(app='word', title='双面打印要留装订线，页码却左右不齐',
         why='默认页边距是左右对称，双面打印装订侧会吃掉内容',
         how=['布局 → 页边距 → 自定义边距 → 页码范围 → 多页选「对称页边距」',
              '装订线设 2.5~3 cm，位置选「左」',
              '页码放页脚外侧：页脚 → 页码 → 页边距 → 选「外侧」'],
         note='交给打印店前导一份 PDF，让对方按 PDF 打，别让他“帮你调”'),

    # ---------------- Excel ----------------
    dict(app='excel', title='身份证号/长数字变成 4.56E+17，后三位变 000',
         why='Excel 数字精度只有 15 位，超了就被截断并转成科学计数',
         how=['输入前：把该列设为「文本」格式，或先输一个英文单引号 \'',
              '已录入的：设成文本后重新输入（改格式不会恢复已丢的位数）',
              '从别处粘贴：先粘到记事本，再粘进文本格式的列',
              'CSV 导入时在向导第一步就把该列指定为“文本”'],
         note='已经被截断的只能重录，数字本身已丢失'),
    dict(app='excel', title='CSV 双击打开全是乱码',
         why='Excel 双击按系统默认编码（GBK）读，而文件是 UTF-8',
         how=['别双击：数据 → 从文本/CSV → 选文件 → 文件原始格式选 65001: Unicode (UTF-8)',
              '要长期用：另存为 .xlsx，或导出 CSV 时选「CSV UTF-8」',
              '已经在表格里：数据 → 自文本导入，重建连接'],
         note='带中文的 CSV 一律走“从文本/CSV”导入'),
    dict(app='excel', title='筛选之后复制粘贴，粘到了隐藏行上',
         why='默认复制包含隐藏单元格，粘贴会错位',
         how=['筛选后：选中区域 → Ctrl+G → 定位条件 → 勾「可见单元格」→ 确定',
              '再 Ctrl+C 复制，然后粘贴',
              '或者用 Alt+;（分号）快捷键直接选中可见单元格'],
         note='Alt+; 是这条的救命键'),
    dict(app='excel', title='SUM 求和结果是 0，或者合计对不上',
         why='单元格里的数字其实是文本（带空格、全角、绿色小三角）',
         how=['选中列 → 数据 → 分列 → 直接点完成（强制转数值）',
              '或整列乘 1：空白单元格输 1 → 复制 → 选择性粘贴 → 乘',
              '从系统导出的数据常带前后空格：用 TRIM() 清洗',
              '看状态栏：选中后状态栏不显示“求和”，就是文本'],
         note='绿色三角 = 文本型数字，一眼能认'),
    dict(app='excel', title='合并单元格后不能排序、不能做透视表',
         why='合并格破坏了“一行一条记录”的结构',
         how=['取消合并：选中 → 开始 → 合并后居中（点掉）',
              '空出来的格用「定位条件 → 空值 → =↑ 上一格 → Ctrl+Enter」填充',
              '只在标题行/表头用合并，数据区永不合并',
              '已经合并很多：用「开始 → 查找 → 定位 → 空值」批量回填后再排序'],
         note='数据表的第一原则：一格一个值，不做合并'),
    dict(app='excel', title='日期显示成 45000 这样的数字',
         why='单元格格式被设成了“常规/数值”，日期本质是序列号',
         how=['选中列 → Ctrl+1 → 数字 → 日期 → 选格式',
              '想自定义：自定义格式输入 yyyy-mm-dd',
              '导入的数据是文本日期：数据 → 分列 → 第三步选「日期 YMD」'],
         note='45000 左右 = 2023 年，不是数据错了'),
    dict(app='excel', title='VLOOKUP 明明有却返回 #N/A',
         why='两边格式不一致（一边文本一边数值）、或有多余空格、或没锁定查找列',
         how=['先查格式：=ISNUMBER(A2) 与 =ISNUMBER(查找值) 结果要一致',
              '清空格：=TRIM(A2)，或查找值套 TRIM',
              '第四参数写 0（精确匹配）',
              '区域要用绝对引用：$A$2:$D$100，否则下拉就错位'],
         note='老版本没有 XLOOKUP，用 IFERROR(VLOOKUP(...),"") 包一层更干净'),
    dict(app='excel', title='提示“循环引用”，或者公式结果一直是 0',
         why='公式把自己所在的单元格算进去了',
         how=['公式 → 错误检查 → 循环引用 → 点它给的位置',
              '改公式，避开自身单元格',
              '迭代计算别乱开（文件 → 选项 → 公式），会掩盖真问题'],
         note='循环引用通常是拉公式时引用范围写错了一格'),
    dict(app='excel', title='条件格式不生效，或者复制到别的表就错乱',
         why='规则的作用范围没跟着走，或用了相对引用',
         how=['开始 → 条件格式 → 管理规则 → 看「应用于」范围对不对',
              '复制格式用「选择性粘贴 → 格式」，别直接 Ctrl+V',
              '引用写法：整列规则用 =$A2>100（锁列不锁行）'],
         note='规则里 $ 的位置决定它能不能整列套用'),
    dict(app='excel', title='打印出来分页乱七八糟、每页没有表头',
         why='没设打印区域和顶端标题行',
         how=['页面布局 → 打印标题 → 顶端标题行选 $1:$1',
              '页面布局 → 打印区域 → 设置打印区域',
              '视图 → 分页预览，直接拖蓝线调分页',
              '缩放：页面布局 → 宽度选「1 页」，高度选「自动」'],
         note='分页预览里拖蓝线，比猜“缩放到几页”直观'),
    dict(app='excel', title='工作表被保护了，忘了密码改不了',
         why='设置了工作表保护（不是文件打开密码）',
         how=['审阅 → 撤销工作表保护，试试空密码',
              '实在忘了：另存为 .xlsx → 改扩展名为 .zip → 删掉 xl/worksheets/sheet1.xml 里的 sheetProtection 节点 → 改回 .xlsx',
              '以后：保护时把密码记在文件属性的备注里'],
         note='只适用于“工作表保护”；文件打开密码是加密，解不开'),
    dict(app='excel', title='几万行数据卡到不能动',
         why='整列引用、大量易失函数（TODAY/OFFSET/INDIRECT）、条件格式过多',
         how=['把整列引用 A:A 改成具体范围 $A$2:$A$50000',
              '公式贴成数值：复制 → 选择性粘贴 → 值',
              '关掉自动计算：公式 → 计算选项 → 手动，需要时按 F9',
              '数据 → 筛选/排序前先另存一份，避免误操作'],
         note='超过 10 万行考虑用“数据模型/透视表”或直接上数据库'),

    # ---------------- PPT ----------------
    dict(app='ppt', title='换台电脑字体就变了，文字溢出框外',
         why='演示电脑没装你用的字体，系统用替代字体渲染',
         how=['只用系统自带字体：微软雅黑 / 宋体 / 黑体',
              '必须用特殊字体：文件 → 选项 → 保存 → 勾「将字体嵌入文件」',
              '最稳：另存为 PDF 或图片交付',
              '文字溢出：开始 → 段落 → 行距/字号调小，或开启「溢出时缩排文字」'],
         note='投影仪那台电脑的字体永远和你的不一样，别赌'),
    dict(app='ppt', title='插进去的图片变模糊了',
         why='PPT 默认压缩图片（220 ppi 以下）',
         how=['文件 → 选项 → 高级 → 图像大小和质量 → 勾「不压缩文件中的图像」',
              '已模糊的图片：右键 → 更改图片 → 重新插入原图',
              '导出时选 PNG 而不是 JPG'],
         note='截图直接粘贴最容易被压，先存成 PNG 再插入'),
    dict(app='ppt', title='母版/版式改不动，新建页还是老样子',
         why='改的是普通页而不是母版，或者用了“重用幻灯片”带进来的独立格式',
         how=['视图 → 幻灯片母版 → 在母版里改（改完点「关闭母版视图」）',
              '某页不跟随母版：开始 → 重设（重置）该页',
              '版式混乱：右键该页 → 版式 → 重新选一个'],
         note='母版里改一次，全部页面生效；普通页改一百次也只影响一页'),
    dict(app='ppt', title='字号自己变小、文字被缩成一团',
         why='文本框开启了「溢出时缩排文字」',
         how=['选中文本框 → 右键「设置形状格式」→ 文本选项 → 文本框',
              '取消「溢出时缩排文字」',
              '或者直接把文本框拉大 / 减少字数'],
         note='这条和上一条的“文字溢出”是同一个开关的两面'),
    dict(app='ppt', title='4:3 的稿子放到 16:9 屏幕上两边黑边或被拉扁',
         why='页面尺寸和投影比例不一致',
         how=['设计 → 幻灯片大小 → 宽屏(16:9) 或 自定义',
              '切换时会问「最大化/确保适合」，选「确保适合」内容不会被裁',
              '已经变形的：逐页检查图片比例，Ctrl+Z 回不来就只能重排'],
         note='做之前先问一句：会场屏幕是 16:9 还是 4:3'),
    dict(app='ppt', title='动画顺序乱了，点一下全出来',
         why='动画窗格里顺序错，或用了“与上一动画同时”',
         how=['动画 → 动画窗格 → 拖动条目调整顺序',
              '逐条出现：每条设「单击时」',
              '想全部去掉：动画 → 无'],
         note='汇报类 PPT 少用动画，翻页干净利落反而稳'),
    dict(app='ppt', title='导出 PDF / 视频后颜色和字体都变了',
         why='导出时没嵌入字体、视频压缩率默认偏低',
         how=['PDF：文件 → 导出 → 创建 PDF，选项里勾「符合 ISO 19005-1 (PDF/A)」更稳',
              '视频：文件 → 导出 → 创建视频 → 选「全高清 1080p」并调高每秒钟帧数',
              '颜色偏差大：把图片统一转 sRGB'],
         note='给打印店的 PPT 一定导 PDF，别给 pptx'),
    dict(app='ppt', title='里面嵌的 Excel 图表不跟着数据更新',
         why='图表是“图片”粘贴进来的，或者链接断了',
         how=['粘贴时选「保留源格式并链接数据」',
              '已断链：右键图表 → 编辑数据 → 重新指向源文件',
              '要长期稳定：直接把表格做在 PPT 里（插入 → 图表），不走链接'],
         note='链接的图表换台电脑就断，重要汇报建议“就地重做”'),
]

OFFICE_APPS = [('word', 'Word'), ('excel', 'Excel'), ('ppt', 'PPT')]


def _wrap_cn(s, width):
    out, line, w = [], '', 0
    for ch in s:
        cw = 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
        if w + cw > width:
            out.append(line)
            line, w = '', 0
        line += ch
        w += cw
    if line:
        out.append(line)
    return out or ['']


def _office_app_name(key):
    for k, name in OFFICE_APPS:
        if k == key:
            return name
    return key


def office_menu():
    print()
    rows = ['',
            '  ' + paint('⑤ 办公软件疑难杂症', '1;36')
            + paint('   —   选一条，直接给解法', '90'),
            '']
    for i, (key, name) in enumerate(OFFICE_APPS, 1):
        n = len([t for t in OFFICE_TIPS if t['app'] == key])
        rows.append('   ' + paint('[%d]' % i, '1;33') + '   %-6s' % name
                    + paint('%d 条' % n, '90'))
    rows += ['', '   ' + paint('0', '1;33') + ' 回主界面    '
             + paint('q', '1;33') + ' 退出', '']
    print(_box(rows))
    print('  ' + paint('请选择 1 / 2 / 3', '1') + paint('（0 返回）', '90')
          + paint(' : ', '1'), end='')


def office_list(app):
    items = [t for t in OFFICE_TIPS if t['app'] == app]
    print()
    rows = ['',
            '  ' + paint(_office_app_name(app), '1;36')
            + paint('  共 %d 条' % len(items), '90'),
            '']
    for i, t in enumerate(items, 1):
        for j, part in enumerate(_wrap_cn(t['title'], BOX_W - 12)):
            prefix = ('   ' + paint('[%2d]' % i, '1;33') + ' ') if j == 0 else '        '
            rows.append(prefix + part)
    rows += ['', '   ' + paint('0', '1;33') + ' 返回分类    '
             + paint('q', '1;33') + ' 退出', '']
    print(_box(rows))
    print('  ' + paint('输入编号看解法', '1') + paint('（0 返回）', '90')
          + paint(' : ', '1'), end='')


def office_tip(app, num):
    items = [t for t in OFFICE_TIPS if t['app'] == app]
    try:
        idx = int(num)
    except ValueError:
        idx = 0
    if idx < 1 or idx > len(items):
        print()
        print('  ' + paint('没有第 %s 条，输入 1-%d 之间的编号' % (num, len(items)), '1;31'))
        return
    t = items[idx - 1]
    width = BOX_W - 4
    rows = ['',
            '  ' + paint('%s 第 %d 条' % (_office_app_name(app), idx), '1;36'),
            '']
    for part in _wrap_cn('现象：' + t['title'], width):
        rows.append('  ' + part)
    rows.append('')
    for part in _wrap_cn('原因：' + t['why'], width):
        rows.append('  ' + paint(part, '90'))
    rows.append('')
    rows.append('  ' + paint('解决：', '1;33'))
    for i, step in enumerate(t['how'], 1):
        first = True
        for part in _wrap_cn(step, width - 4):
            rows.append(('   %d. ' % i if first else '      ') + part)
            first = False
    if t.get('note'):
        rows.append('')
        for part in _wrap_cn('提示：' + t['note'], width):
            rows.append('  ' + paint(part, '32'))
    rows += ['', '   ' + paint('0', '1;33') + ' 返回列表    '
             + paint('q', '1;33') + ' 退出', '']
    print(_box(rows))
    print('  ' + paint('回车继续看列表', '90') + paint(' : ', '1'), end='')

STATE_FILE = os.path.join(tempfile.gettempdir(), 'pdfsplit_nametpl.txt')


def load_name_template():
    try:
        with open(STATE_FILE, 'r', encoding='utf-8') as fh:
            return fh.read().strip()
    except Exception:
        return ''


def save_name_template(tpl):
    try:
        if tpl:
            with open(STATE_FILE, 'w', encoding='utf-8') as fh:
                fh.write(tpl)
        elif os.path.exists(STATE_FILE):
            os.remove(STATE_FILE)
    except Exception:
        pass


# ---------- 打开保存目录 ----------

def _stdin_is_tty():
    """界面是真人窗口才询问；被重定向（脚本调用）就不问，免得卡住。"""
    try:
        return sys.stdin is not None and sys.stdin.isatty()
    except Exception:
        return False


def open_folder(path):
    """用资源管理器打开目录。"""
    try:
        if hasattr(os, 'startfile'):
            os.startfile(path)                       # Windows
        else:
            import subprocess
            subprocess.Popen(['xdg-open', path])
        return True
    except Exception as exc:
        print('   打开目录失败: %s' % exc)
        print('   保存目录: %s' % path)
        return False


def ask_open_folder(path, mode='ask'):
    """mode: ask = 询问, yes = 直接打开, no = 不打开。"""
    if not path or not os.path.isdir(path):
        return
    if mode == 'no':
        return
    if mode == 'ask':
        if not _stdin_is_tty():
            print('   保存目录: %s' % path)
            return
        try:
            ans = input('   是否打开保存目录? [y/N] ').strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            ans = ''
        if ans not in ('y', 'yes', '是', '好'):
            print('   保存目录: %s' % path)
            return
    open_folder(path)


# ---------- 极简 PDF 解析：读对象、找图片、按出现顺序排列 ----------

def parse_objects(data):
    out = []
    for m in re.finditer(rb'(?<![0-9])(\d{1,10})\s+(\d{1,5})\s+obj\b', data):
        num = int(m.group(1))
        start = m.end()
        nxt = re.search(rb'(?<![0-9])\d{1,10}\s+\d{1,5}\s+obj\b', data[start:])
        end = start + nxt.start() if nxt else len(data)
        body = data[start:end]
        sm = re.search(rb'stream\r?\n', body)
        if sm:
            db = body[:sm.start()]
            raw = body[sm.end():]
            em = raw.rfind(b'endstream')
            out.append((num, db, raw[:em] if em != -1 else raw))
        else:
            out.append((num, body[:body.rfind(b'endobj')] if b'endobj' in body else body, None))
    return out


def inflate(raw):
    import zlib
    try:
        return zlib.decompress(raw)
    except Exception:
        try:
            return zlib.decompressobj().decompress(raw)
        except Exception:
            return raw


def _inline_dict(text, start):
    depth, i = 0, start
    while i < len(text) - 1:
        if text[i:i + 2] == b'<<':
            depth += 1
            i += 2
            continue
        if text[i:i + 2] == b'>>':
            depth -= 1
            i += 2
            if depth == 0:
                return text[start:i]
            continue
        i += 1
    return b''


def _sub_dict(objmap, db, key):
    m = re.search(rb'/' + key + rb'\s*(\d+\s+\d+\s+R|<<)', db)
    if not m:
        return b''
    if m.group(1).endswith(b'R'):
        n = int(m.group(1).split()[0])
        return objmap.get(n, (b'', b''))[0]
    return _inline_dict(db, db.find(b'<<', m.start()))


def page_image_order(db, objmap, data):
    """返回该页按内容流顺序绘制的图片对象号。"""
    resdb = _sub_dict(objmap, db, b'Resources')
    xdb = _sub_dict(objmap, resdb, b'XObject')
    xmap = {}
    for m in re.finditer(rb'/([A-Za-z0-9#_.+-]+)\s+(\d+)\s+\d+\s+R', xdb):
        xmap[m.group(1).decode('latin-1')] = int(m.group(2))
    cm = re.search(rb'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)', db)
    content = b''
    if cm:
        for r in re.findall(rb'(\d+)\s+\d+\s+R', cm.group(1)):
            raw = objmap.get(int(r), (b'', b''))[1]
            if raw:
                content += inflate(raw) + b'\n'
    order = []
    for m in re.finditer(rb'/([A-Za-z0-9#_.+-]+)\s+Do\b', content):
        name = m.group(1).decode('latin-1')
        if name in xmap and xmap[name] not in order:
            order.append(xmap[name])
    return order


def _image_item(objmap, oid, page_no, rotate):
    idb, raw = objmap.get(oid, (b'', None))
    if b'/Image' not in idb or raw is None:
        return None
    wm = re.search(rb'/Width\s+(\d+)', idb)
    hm = re.search(rb'/Height\s+(\d+)', idb)
    if not wm or not hm:
        return None
    f = re.search(rb'/Filter\s*(\[[^\]]*\]|/\w+)', idb)
    filt = f.group(1).decode('latin-1').replace(' ', '') if f else ''
    return dict(page=page_no, w=int(wm.group(1)), h=int(hm.group(1)), filt=filt,
                raw=raw, digest=hashlib.md5(raw).hexdigest(), rotate=rotate)


def analyse_pdf(path):
    with open(path, 'rb') as fh:
        data = fh.read()
    objs = parse_objects(data)
    objmap = {o[0]: (o[1], o[2]) for o in objs}
    pages = [o[0] for o in objs if re.search(rb'/Type\s*/Page(?![sA-Za-z])', o[1])]
    items = []
    if pages:
        for pi, pn in enumerate(pages, 1):
            db = objmap[pn][0]
            rm = re.search(rb'/Rotate\s+(-?\d+)', db)
            rotate = (int(rm.group(1)) % 360) if rm else 0
            for oid in page_image_order(db, objmap, data):
                it = _image_item(objmap, oid, pi, rotate)
                if it:
                    items.append(it)
    else:
        # 退路：PDF 用了对象流 / 交叉引用流时页树读不出来，就按对象顺序扫图片
        for oid in sorted(objmap):
            it = _image_item(objmap, oid, 0, 0)
            if it:
                items.append(it)
    return items


# ---------- 方向纠正 ----------

def row_profile_score(im):
    g = im.convert('L')
    g.thumbnail((900, 900))
    a = 255.0 - np.asarray(g, dtype=np.float32)
    rs = a.mean(axis=1) - a.mean(axis=1).mean()
    return float((rs ** 2).mean() / (a.mean() ** 2 + 1e-6))


def upright_image(raw, cw_rotate):
    """按页面 /Rotate 转正，再按文字的横向行特征纠正横躺的扫描件。"""
    im = Image.open(io.BytesIO(raw))
    im.load()
    if im.mode not in ('RGB', 'L'):
        im = im.convert('RGB')
    changed = False
    ccw = (360 - cw_rotate) % 360
    if ccw in (90, 180, 270):
        im = im.transpose({90: Image.ROTATE_90, 180: Image.ROTATE_180,
                           270: Image.ROTATE_270}[ccw])
        changed = True
    straight = im.transpose(Image.ROTATE_90)
    if row_profile_score(straight) > row_profile_score(im) * 1.3:
        im = straight
        changed = True
    return im, changed


# ---------- 生成 A4 PDF（JPEG 原样嵌入，不重新压缩） ----------

def build_pdf(jpeg, w, h, out_path):
    landscape = w >= h
    page_w, page_h = (A4_LONG, A4_SHORT) if landscape else (A4_SHORT, A4_LONG)
    box_w, box_h = page_w - 2 * MARGIN, page_h - 2 * MARGIN
    scale = min(box_w / w, box_h / h)
    dw, dh = w * scale, h * scale
    dx, dy = (page_w - dw) / 2.0, (page_h - dh) / 2.0

    content = ('q\n%.4f 0 0 %.4f %.4f %.4f cm\n/Im0 Do\nQ\n'
               % (dw, dh, dx, dy)).encode('ascii')
    objs = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        ('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] '
         '/Resources << /XObject << /Im0 4 0 R >> /ProcSet [/PDF /ImageC] >> '
         '/Contents 5 0 R >>' % (page_w, page_h)).encode('ascii'),
        ('<< /Type /XObject /Subtype /Image /Width %d /Height %d '
         '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode '
         '/Interpolate true /Length %d >>\nstream\n' % (w, h, len(jpeg))
         ).encode('ascii') + jpeg + b'\nendstream',
        b'<< /Length %d >>\nstream\n' % len(content) + content + b'endstream',
    ]
    out = io.BytesIO()
    out.write(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offsets = []
    for i, body in enumerate(objs, 1):
        offsets.append(out.tell())
        out.write(b'%d 0 obj\n' % i + body + b'\nendobj\n')
    xref = out.tell()
    out.write(b'xref\n0 %d\n' % (len(objs) + 1))
    out.write(b'0000000000 65535 f \n')
    for off in offsets:
        out.write(b'%010d 00000 n \n' % off)
    out.write(b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n'
              % (len(objs) + 1, xref))
    with open(out_path, 'wb') as f:
        f.write(out.getvalue())


# ---------- 主流程 ----------

def safe_stem(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    stem = re.sub(r'[（(]\s*\d+\s*[）)]$', '', stem).strip() or 'PDF'
    return re.sub(r'[\\/:*?"<>|]', '_', stem)


def expand_template(tpl, idx, page, pdf_path):
    """把 --name 模板展开成文件名（不含扩展名），并清掉非法字符。"""
    pdf_stem = safe_stem(pdf_path)
    values = {
        'n': str(idx),
        'nn': '%02d' % idx,
        'nnn': '%03d' % idx,
        'page': str(page) if page else str(idx),
        'pdf': pdf_stem,
        'date': time.strftime('%Y%m%d'),
    }

    def repl(m):
        key = m.group(1).lower()
        return values.get(key, m.group(0))

    out = re.sub(r'\{([A-Za-z_]+)\}', repl, tpl or '')
    out = re.sub(r'[\\/:*?"<>|\r\n\t]', '_', out).strip(' .')
    return out or defaults_name(idx)


def defaults_name(idx):
    return '%d组' % idx


def normalize_tpl(val):
    """用户只写“周例会”这种名字时，自动补成“周例会-{n}”。"""
    v = (val or '').strip().strip('"').strip()
    if not v:
        return ''
    if '{' not in v:
        v = v + '-{n}'
    return v


def describe_template(tpl):
    """把模板翻成人话，给菜单显示用。"""
    if not tpl:
        return '1组、2组、3组 ……（默认）'
    if tpl == '{pdf}-{n}':
        return '原PDF名+序号，如 会议纪要-1、会议纪要-2 ……'
    a = expand_template(tpl, 1, 1, 'PDF文件名示例.pdf')
    b = expand_template(tpl, 2, 2, 'PDF文件名示例.pdf')
    return '如 %s.jpg、%s.jpg ……' % (a, b)


def unique_base(folder, base, used):
    """重名（模板里没有唯一占位符）时加 -2、-3 后缀。"""
    cand, n = base, 2
    while cand.lower() in used:
        cand = '%s-%d' % (base, n)
        n += 1
    used.add(cand.lower())
    return cand


def process_pdf(pdf, out_root, want_jpg=True, want_pdf=True, name_tpl=None):
    items = analyse_pdf(pdf)
    cnt = Counter(i['digest'] for i in items)
    kept = [i for i in items if cnt[i['digest']] < 2]     # 跳过每页重复的页眉模板图

    name = safe_stem(pdf)
    folder = os.path.join(out_root, name)
    n = 2
    while os.path.isdir(folder) and os.listdir(folder) and not any(
            re.match(r'^.+\.(jpg|pdf)$', f, re.I) for f in os.listdir(folder)):
        folder = os.path.join(out_root, '%s_%d' % (name, n))
        n += 1
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):                 # 清掉上一次运行留下的旧图/旧 PDF
        if f.lower().endswith(('.jpg', '.pdf')):
            os.remove(os.path.join(folder, f))

    made = []
    used = set()
    idx = 0
    for i in kept:
        try:
            im, changed = upright_image(i['raw'], i['rotate'])
        except Exception as exc:
            print('   跳过一张无法解码的图: %s' % exc)
            continue
        idx += 1
        shown = expand_template(name_tpl, idx, i['page'], pdf) if name_tpl else defaults_name(idx)
        base_name = unique_base(folder, shown, used)
        base = os.path.join(folder, base_name)
        jpg_path = base + '.jpg'
        if not changed and 'DCTDecode' in i['filt']:
            jpeg = i['raw']                       # 原样使用，零重压
        else:
            buf = io.BytesIO()
            im.save(buf, 'JPEG', quality=95, subsampling=0, optimize=True)
            jpeg = buf.getvalue()
        if want_jpg:
            with open(jpg_path, 'wb') as f:
                f.write(jpeg)
        if want_pdf:
            build_pdf(jpeg, im.width, im.height, base + '.pdf')
        made.append((base_name, i['page'], im.width, im.height, changed))
    return made, len(items) - len(kept), folder


# ---------- 压缩 PDF 体积 ----------

def _pdf_root_ref(data):
    m = re.search(rb'trailer\s*<<(.*?)>>\s*startxref', data, re.S)
    if not m:
        return None
    r = re.search(rb'/Root\s+(\d+)\s+(\d+)\s+R', m.group(1))
    if not r:
        return None
    return int(r.group(1)), int(r.group(2))


def _img_dict(w, h, cs, length):
    return ('<< /Type /XObject /Subtype /Image /Width %d /Height %d '
            '/ColorSpace /%s /BitsPerComponent 8 /Filter /DCTDecode '
            '/Interpolate true /Length %d >>'
            % (w, h, cs, length)).encode('ascii')


def _open_image(raw):
    try:
        im = Image.open(io.BytesIO(raw))
        im.load()
        return im
    except Exception:
        return None


def _to_jpeg(im, quality, scale=1.0):
    """重新编码成 JPEG，返回 (bytes, w, h, colorspace)。"""
    out = im
    if scale < 0.999:
        out = im.resize((max(1, int(im.width * scale)),
                         max(1, int(im.height * scale))), Image.LANCZOS)
    if out.mode in ('RGBA', 'LA', 'P', 'PA', '1', 'I', 'F'):
        out = out.convert('RGB')
    elif out.mode not in ('RGB', 'L', 'CMYK'):
        out = out.convert('RGB')
    q = int(max(5, min(95, quality)))
    buf = io.BytesIO()
    out.save(buf, 'JPEG', quality=q, optimize=True,
             subsampling=0 if q >= 90 else 2)
    cs = {'L': 'DeviceGray', 'CMYK': 'DeviceCMYK'}.get(out.mode, 'DeviceRGB')
    return buf.getvalue(), out.width, out.height, cs


def compress_pdf(src, out_path, target_bytes=None, say=print):
    """只替换里面的图片对象，页面、文字、书签全部原样保留。"""
    with open(src, 'rb') as fh:
        data = fh.read()
    root = _pdf_root_ref(data)
    if not root:
        return None, 'PDF 结构较新（交叉引用流），暂不支持压缩'
    if re.search(rb'(?<![0-9])\d+\s+[1-9]\d*\s+obj\b', data):
        return None, 'PDF 里有非 0 版本的间接对象，暂不支持压缩'
    objs = parse_objects(data)
    if not objs:
        return None, 'PDF 解析失败'
    objmap = {o[0]: (o[1], o[2]) for o in objs}
    for num, db, raw in objs:
        if b'/ObjStm' in db or b'/XRef' in db or b'/Encrypt' in db:
            return None, 'PDF 用了对象流或加密，暂不支持压缩'

    pics = {}
    for num, db, raw in objs:
        if b'/Image' not in db or raw is None:
            continue
        if b'/SMask' in db or b'/Mask' in db:      # 带透明蒙版的跳过，免得花掉
            continue
        im = _open_image(raw)
        if im is not None:
            pics[num] = (im, len(raw))
    if not pics:
        return None, '里面没有可压缩的图片（多半是纯文字版 PDF）'

    keep = 0
    for num, db, raw in objs:
        if num not in pics:
            keep += len(db) + (len(raw) if raw else 0)
    base = keep + 800 * len(objs)

    def attempt(quality, scale):
        total, blobs = base, {}
        for num, (im, _old) in pics.items():
            jpeg, w, h, cs = _to_jpeg(im, quality, scale)
            blobs[num] = (jpeg, w, h, cs)
            total += len(jpeg) + 300
        return total, blobs

    if target_bytes:
        lo, hi, pick = 12, 92, None
        while lo <= hi:
            q = (lo + hi) // 2
            total, blobs = attempt(q, 1.0)
            say('   试压 质量%d → 约 %.2f MB' % (q, total / 1048576.0))
            if total <= target_bytes:
                pick = (q, 1.0, blobs)
                lo = q + 1
            else:
                hi = q - 1
        if pick is None:                            # 只降质量不够，再缩分辨率
            for sc in (0.85, 0.7, 0.55, 0.45, 0.35):
                for q in (70, 55, 40, 25):
                    total, blobs = attempt(q, sc)
                    say('   试压 质量%d 缩放%d%% → 约 %.2f MB'
                        % (q, sc * 100, total / 1048576.0))
                    if total <= target_bytes:
                        pick = (q, sc, blobs)
                        break
                if pick:
                    break
        if pick is None:
            q, sc = 25, 0.35
            total, blobs = attempt(q, sc)
            pick = (q, sc, blobs)
            say('   [i] 已经压到最小了，还是约 %.2f MB，先按这个给你'
                % (total / 1048576.0))
        quality, scale, blobs = pick
    else:
        quality = 75
        big = max(max(im.width, im.height) for im, _ in pics.values())
        scale = min(1.0, 2480.0 / big) if big > 2480 else 1.0
        total, blobs = attempt(quality, scale)
        say('   自动参数：质量 75，长边上限 2480 像素 → 约 %.2f MB'
            % (total / 1048576.0))

    _rebuild_pdf(objs, root, blobs, out_path, objmap)
    return os.path.getsize(out_path), 'ok'


def _stream_len(body, raw, objmap=None):
    """取 /Length 的真实值；它可能是间接引用（/Length 8 0 R），不能直接用对象号。"""
    lm = re.search(rb'/Length\s+(\d+)(\s+\d+\s+R)?', body)
    if not lm:
        return len(raw)
    n = int(lm.group(1))
    if lm.group(2) and objmap is not None:
        val = objmap.get(n, (b'', None))[0].strip()
        try:
            n = int(val)
        except (TypeError, ValueError):
            return len(raw)
    if n < 0 or n > len(raw) + 64:
        return len(raw)
    return n


def _rebuild_pdf(objs, root, blobs, out_path, objmap=None):
    """按原对象顺序重写整个 PDF；blobs 里的对象用新图片替换，其余原样搬过去。"""
    buf = io.BytesIO()
    buf.write(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offs, maxnum = {}, 0
    for num, db, raw in objs:
        maxnum = max(maxnum, num)
        offs[num] = buf.tell()
        buf.write(b'%d 0 obj\n' % num)
        if num in blobs:
            jpeg, w, h, cs = blobs[num]
            buf.write(_img_dict(w, h, cs, len(jpeg)))
            buf.write(b'\nstream\n' + jpeg + b'\nendstream\n')
        else:
            body = db.strip()
            buf.write(body)
            if raw is not None:
                cut = _stream_len(body, raw, objmap)
                buf.write(b'\nstream\n' + raw[:cut] + b'\nendstream\n')
            else:
                buf.write(b'\n')
        buf.write(b'endobj\n')
    xref = buf.tell()
    size = maxnum + 1
    buf.write(b'xref\n0 %d\n' % size)
    buf.write(b'0000000000 65535 f \n')
    for i in range(1, size):
        if i in offs:
            buf.write(b'%010d 00000 n \n' % offs[i])
        else:
            buf.write(b'0000000000 65535 f \n')
    buf.write(b'trailer\n<< /Size %d /Root %d %d R >>\nstartxref\n%d\n%%%%EOF\n'
              % (size, root[0], root[1], xref))
    with open(out_path, 'wb') as fh:
        fh.write(buf.getvalue())


def compress_file(pdf, target_bytes=None, say=print):
    stem = os.path.splitext(pdf)[0]
    out = stem + '_压缩.pdf'
    n = 2
    while os.path.exists(out):
        out = '%s_压缩%d.pdf' % (stem, n)
        n += 1
    old = os.path.getsize(pdf)
    say('   原大小：%.2f MB' % (old / 1048576.0))
    size, info = compress_pdf(pdf, out, target_bytes, say)
    if size is None:
        return None, info
    say('   压缩后：%.2f MB  →  %s' % (size / 1048576.0, os.path.basename(out)))
    if size >= old:
        say('   [i] 这份本来就很小，压不动；新的反而略大，建议用原文件')
    return size, out


# ---------- 水印探测 / 去除（对象级，无损） ----------

def _page_xobjects(objmap, page_num):
    """页面 Resources 里的 {名字: 对象号}。"""
    resdb = _sub_dict(objmap, objmap[page_num][0], b'Resources')
    xdb = _sub_dict(objmap, resdb, b'XObject')
    mp = {}
    for mm in re.finditer(rb'/([A-Za-z0-9#_.+-]+)\s+(\d+)\s+\d+\s+R', xdb):
        mp[mm.group(1).decode('latin-1')] = int(mm.group(2))
    return mp


def _content_text(objmap, page_db):
    """把一页的内容流拼起来（顺带解压），返回 (bytes, [(对象号, 是否压缩)])。"""
    cm = re.search(rb'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)', page_db)
    if not cm:
        return b'', []
    txt, parts = b'', []
    for r in re.findall(rb'(\d+)\s+\d+\s+R', cm.group(1)):
        num = int(r)
        db, raw = objmap.get(num, (b'', None))
        if raw is None:
            continue
        packed = b'/FlateDecode' in db
        txt += (inflate(raw) if packed else raw) + b'\n'
        parts.append((num, packed))
    return txt, parts


def _do_position(content, name):
    """从内容流里找出 /Name Do 之前的平移量，用来在预览图上画框。"""
    pat = re.compile(rb'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+cm\s*\n?\s*'
                     rb'([-\d.]+)\s+([-\d.]+)\s+0\s+0\s+0\s+0\s+cm\s*\n?\s*/'
                     + re.escape(name.encode('latin-1')) + rb'\s+Do')
    m = pat.search(content)
    if not m:
        m2 = re.search(rb'([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+cm\s*\n?\s*/'
                       + re.escape(name.encode('latin-1')) + rb'\s+Do', content)
        if not m2:
            return None
        g = [float(x) for x in m2.groups()]
        return g[4], g[5], g[0], g[3]
    g = [float(x) for x in m.groups()]
    w, h = g[6], g[7]
    return g[4], g[5], w, h


def find_watermarks(pdf, say=print):
    """找出“每页都贴、尺寸又明显更小”的重复图片对象 = 水印候选。"""
    with open(pdf, 'rb') as fh:
        data = fh.read()
    objs = parse_objects(data)
    objmap = {o[0]: (o[1], o[2]) for o in objs}
    pages = [o[0] for o in objs if re.search(rb'/Type\s*/Page(?![sA-Za-z])', o[1])]
    if not pages:
        return None, '读不出页面结构（可能是对象流 PDF）'
    per_page, seen = {}, {}
    for pn in pages:
        mp = _page_xobjects(objmap, pn)
        per_page[pn] = mp
        for name, oid in mp.items():
            seen.setdefault(oid, []).append((pn, name))
    # 按内容 md5 分组：扫描软件常常每页放一份“内容相同、对象号不同”的水印
    groups = {}
    for oid, uses in seen.items():
        idb, raw = objmap.get(oid, (b'', None))
        if b'/Image' not in idb or raw is None:
            continue
        wm = re.search(rb'/Width\s+(\d+)', idb)
        hm = re.search(rb'/Height\s+(\d+)', idb)
        if not wm or not hm:
            continue
        h = hashlib.md5(raw).hexdigest()
        g = groups.setdefault(h, dict(oids=[], uses=[], raw=raw,
                                      w=int(wm.group(1)), h=int(hm.group(1))))
        g['oids'].append(oid)
        g['uses'].extend(uses)
    cands = []
    for h, g in groups.items():
        pset = set(pn for pn, _n in g['uses'])
        if len(pset) < max(2, int(len(pages) * 0.8)):
            continue
        cands.append(dict(oids=g['oids'], name=g['uses'][0][1], uses=g['uses'],
                          w=g['w'], h=g['h'], area=g['w'] * g['h'], raw=g['raw'],
                          pages=len(pset)))
    if not cands:
        return dict(pages=len(pages), cands=[], objmap=objmap, objs=objs,
                    page_nums=pages, per_page=per_page), 'ok'
    # 水印一定是“比正文那页小得多”的：用每页最大图做参照
    page_area = 0
    for pn in pages[:1]:
        for name, oid in per_page[pn].items():
            idb, raw = objmap.get(oid, (b'', None))
            wm = re.search(rb'/Width\s+(\d+)', idb)
            hm = re.search(rb'/Height\s+(\d+)', idb)
            if wm and hm:
                page_area = max(page_area, int(wm.group(1)) * int(hm.group(1)))
    cands = [c for c in cands if page_area == 0 or c['area'] < page_area * 0.25]
    cands.sort(key=lambda c: c['area'])
    return dict(pages=len(pages), cands=cands, objmap=objmap, objs=objs,
                page_nums=pages, per_page=per_page, page_area=page_area), 'ok'


def _wm_report(pdf, info, open_preview=False, say=print):
    if not info['cands']:
        say('   共 %d 页，没发现“每页都贴的重复图片”' % info['pages'])
        say('   （这份 PDF 的水印可能是烧进像素里的，不是独立对象）')
        return None
    say('   共 %d 页，发现 %d 个“每页都出现”的图片对象：'
        % (info['pages'], len(info['cands'])))
    stem = os.path.splitext(pdf)[0]
    imgs = []
    for c in info['cands']:
        im = _open_image(c['raw'])
        if im is None:
            continue
        imgs.append((c, im))
        say('   · %dx%d 像素，贴在 %d 页上，位置在每页的 %s'
            % (c['w'], c['h'], c['pages'], _wm_pos(info, c)))
    if not imgs:
        return None
    # 水印样本 + 在页面上的位置
    c0, im0 = imgs[0]
    pw = 560
    th = max(60, int(im0.height * pw / im0.width))
    thumb = im0.convert('RGB').resize((pw, min(th, 220)), Image.LANCZOS)
    page_im = _page_image(info, info['page_nums'][0])
    pv = None
    box = None
    content, _parts = _content_text(info['objmap'], info['objmap'][info['page_nums'][0]][0])
    box = _do_position(content, c0['name'])
    if page_im is not None:
        w = 560
        h = max(1, int(page_im.height * w / page_im.width))
        pv = page_im.convert('RGB').resize((w, h), Image.LANCZOS)
        if box:
            x, y, bw, bh = box
            mb = re.search(rb'/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]',
                           info['objmap'][info['page_nums'][0]][0])
            if mb:
                x0, y0, x1, y1 = [float(v) for v in mb.groups()]
                sx = w / max(1e-6, (x1 - x0))
                sy = h / max(1e-6, (y1 - y0))
                rx = (x - x0) * sx
                ry = (y1 - (y + bh)) * sy
                pv = pv.copy()
                cv = np.array(pv)
                for t in range(4):
                    yy = int(ry) + t
                    if 0 <= yy < h:
                        cv[yy, max(0, int(rx)):min(w, int(rx + bw * sx))] = [255, 0, 0]
                    yy = int(ry + bh * sy) + t
                    if 0 <= yy < h:
                        cv[yy, max(0, int(rx)):min(w, int(rx + bw * sx))] = [255, 0, 0]
                    xx = int(rx) + t
                    if 0 <= xx < w:
                        cv[max(0, int(ry)):min(h, int(ry + bh * sy)), xx] = [255, 0, 0]
                    xx = int(rx + bw * sx) + t
                    if 0 <= xx < w:
                        cv[max(0, int(ry)):min(h, int(ry + bh * sy)), xx] = [255, 0, 0]
                pv = Image.fromarray(cv)
    out = stem + '_水印预览.png'
    if pv is not None:
        panel = Image.new('RGB', (1120 + 16, max(pv.height, thumb.height) + 40), 'white')
        panel.paste(pv, (0, 20))
        panel.paste(thumb, (576, 20 + 0))
        panel.save(out)
    else:
        thumb.save(out)
    say('   预览图：%s（左边是页面，红框标出水印位置；右边是水印本身）'
        % os.path.basename(out))
    if open_preview:
        try:
            os.startfile(out)
        except Exception:
            pass
    return out


def _page_image(info, page_num):
    best = None
    for name, oid in info['per_page'][page_num].items():
        idb, raw = info['objmap'].get(oid, (b'', None))
        if b'/Image' not in idb or raw is None:
            continue
        wm = re.search(rb'/Width\s+(\d+)', idb)
        hm = re.search(rb'/Height\s+(\d+)', idb)
        if not wm or not hm:
            continue
        a = int(wm.group(1)) * int(hm.group(1))
        if best is None or a > best[0]:
            best = (a, raw)
    if best is None:
        return None
    return _open_image(best[1])


def _wm_pos(info, cand):
    content, _ = _content_text(info['objmap'], info['objmap'][info['page_nums'][0]][0])
    box = _do_position(content, cand['name'])
    if not box:
        return '（位置读不到）'
    mb = re.search(rb'/MediaBox\s*\[\s*([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*\]',
                   info['objmap'][info['page_nums'][0]][0])
    if not mb:
        return '（位置读不到）'
    x0, y0, x1, y1 = [float(v) for v in mb.groups()]
    cx = (box[0] + box[2] / 2 - x0) / max(1e-6, x1 - x0)
    cy = 1 - (box[1] + box[3] / 2 - y0) / max(1e-6, y1 - y0)
    return _where(cx, cy)


def _where(cx, cy):
    v = '上' if cy < 0.34 else ('中' if cy < 0.67 else '下')
    h = '左' if cx < 0.34 else ('中' if cx < 0.67 else '右')
    return h + v


def scan_watermark(pdf, open_preview=False, say=print):
    """只扫描不动手：报告每页重复的图片对象，并生成预览。"""
    info, msg = find_watermarks(pdf, say)
    if info is None:
        return None, msg
    png = _wm_report(pdf, info, open_preview, say)
    info['png'] = png
    return info, 'ok'


def strip_watermark(pdf, say=print):
    info, msg = find_watermarks(pdf, say)
    if info is None:
        return None, msg
    if not info['cands']:
        return None, '没找到“每页重复的图片水印”，这份 PDF 的水印可能是烧进像素里的'
    root = _pdf_root_ref(open(pdf, 'rb').read())
    if not root:
        return None, 'PDF 结构较新（交叉引用流），暂不支持改写'
    objmap, objs = info['objmap'], info['objs']
    kill = set()
    names_by_page = {}
    for c in info['cands']:
        for _o in c['oids']:
            kill.add(_o)
        for pn, name in c['uses']:
            names_by_page.setdefault(pn, set()).add(name)
    new_objs = []
    removed = 0
    for num, db, raw in objs:
        new_objs.append((num, db, raw))
    # 1) 页面 Resources 里去掉这些 XObject
    by_num = {o[0]: [o[1], o[2]] for o in new_objs}
    for pn, names in names_by_page.items():
        db = by_num[pn][0]
        for name in names:
            db = re.sub(rb'\s*/' + re.escape(name.encode('latin-1')) + rb'\s+\d+\s+\d+\s+R', b'', db, count=1)
        by_num[pn][0] = db
    # 2) 内容流里去掉 /Name Do
    for pn, names in names_by_page.items():
        content, parts = _content_text(objmap, objmap[pn][0])
        if not content:
            continue
        newc = content
        for name in names:
            pat = re.compile(rb'[qQ]\s*\n?\s*([-\d.]+\s+){6}cm\s*\n?\s*([-\d.]+\s+){6}cm\s*\n?\s*/'
                             + re.escape(name.encode('latin-1')) + rb'\s+Do\s*\n?\s*[qQ]\s*\n?')
            newc2 = pat.sub(b'', newc)
            if newc2 == newc:
                newc2 = re.sub(rb'\s*/' + re.escape(name.encode('latin-1')) + rb'\s+Do\b', b'', newc)
            newc = newc2
        if newc == content:
            continue
        for num_i, packed in parts:
            body = zlib.compress(newc) if packed else newc
            by_num[num_i][0] = re.sub(rb'/Length\s+\d+(\s+\d+\s+R)?', b'/Length %d' % len(body), by_num[num_i][0], count=1)
            by_num[num_i][1] = body
        removed += 1
    if removed == 0:
        return None, '找到了水印对象，但没能在内容流里定位到它的绘制指令'
    new_objs = [(n, by_num[n][0], by_num[n][1]) for n, _d, _r in new_objs]
    stem = os.path.splitext(pdf)[0]
    out = stem + '_去水印.pdf'
    k = 2
    while os.path.exists(out):
        out = '%s_去水印%d.pdf' % (stem, k)
        k += 1
    _rebuild_pdf(new_objs, root, {}, out, by_num)
    say('   已从 %d 页里删掉水印对象（正文、文字、其他图片全部原样保留）' % removed)
    say('   输出：%s' % os.path.basename(out))
    return os.path.getsize(out), out


def remove_watermark(pdf, say=print):
    return strip_watermark(pdf, say)


def collect_pdfs(args, exclude=()):
    """收集 PDF；跳过输出目录，避免把自己的产物又当成输入。"""
    excl = [os.path.abspath(e) for e in exclude if e]
    pdfs, roots = [], []

    def blocked(path):
        ap = os.path.abspath(path)
        for e in excl:
            if ap == e or ap.startswith(e + os.sep):
                return True
        return False

    for a in args:
        if os.path.isdir(a):
            roots.append(a)
            for dirpath, dirs, files in os.walk(a):
                dirs[:] = [d for d in dirs
                           if d != OUT_ROOT_NAME
                           and not blocked(os.path.join(dirpath, d))]
                pdfs += [os.path.join(dirpath, f) for f in files
                         if f.lower().endswith('.pdf')
                         and not blocked(os.path.join(dirpath, f))]
        elif a.lower().endswith('.pdf') and os.path.isfile(a):
            pdfs.append(a)
            roots.append(os.path.dirname(os.path.abspath(a)))
    seen, uniq = set(), []
    for p in pdfs:
        k = os.path.abspath(p).lower()
        if k not in seen:
            seen.add(k)
            uniq.append(p)
    return uniq, roots


def _read_text(path):
    """bat 用 chcp 65001 写出来的清单是 UTF-8，旧系统可能是 GBK，都试一遍。"""
    try:
        with open(path, 'rb') as fh:
            raw = fh.read()
    except OSError:
        return ''
    for enc in ('utf-8-sig', 'gbk', 'utf-16'):
        try:
            return raw.decode(enc)
        except Exception:
            continue
    return raw.decode('latin-1')


def read_path_list(list_file):
    """把 bat 窗口里拖进来的那一行还原成参数（兼容带空格、带引号、多个文件）。"""
    tokens = []
    for line in _read_text(list_file).replace('\r', '\n').split('\n'):
        line = line.strip()
        if not line:
            continue
        bare = line.strip('"').strip()
        if os.path.exists(bare):                 # 整行就是一个路径（可能带空格）
            tokens.append(bare)
            continue
        try:
            parts = shlex.split(line, posix=False)
        except ValueError:
            parts = line.split()
        for p in parts:
            p = p.strip().strip('"').strip()
            if p:
                tokens.append(p)
    return tokens


def expand_from_list(argv):
    out, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in ('--from-list', '--list'):
            if i + 1 < len(argv):
                out.extend(read_path_list(argv[i + 1]))
            i += 2
            continue
        out.append(a)
        i += 1
    return out


def main(argv):
    argv = expand_from_list(argv)
    if any(a in ('--home',) for a in argv):
        print_home()
        return 0
    if '--rename-menu' in argv:
        rename_menu()
        return 0
    if '--rename-template-menu' in argv:
        rename_template_menu()
        return 0
    if '--rename-prefix-prompt' in argv:
        rename_prefix_prompt()
        return 0
    if '--rename-tpl-prompt' in argv:
        rename_tpl_prompt()
        return 0
    if '--rename-undo' in argv:
        rename_undo()
        return 0
    if '--rename-scan' in argv:
        targets = [a for a in argv if not a.startswith('--') and os.path.exists(a)]
        if not targets:
            print('  ' + paint('没有收到路径。把文件夹或文件拖进窗口再回车。', '1;31'))
            return 1
        try:
            st = rename_scan(targets, recurse='--recurse' in argv)
        except Exception as exc:
            print('  ' + paint('扫描失败：%s' % exc, '1;31'))
            if os.environ.get('PDFSPLIT_DEBUG'):
                import traceback
                traceback.print_exc()
            return 1
        if st:
            rename_show(st)
        return 0
    if any(a in ('--rename-show', '--rename-apply', '--rename-mode', '--rename-order',
                 '--rename-prefix-from', '--rename-tpl-from') for a in argv):
        st = _rename_load()
        if not st or not st.get('items'):
            print('  ' + paint('还没有扫描。先把文件夹或文件拖进来。', '1;31'))
            return 1
        changed = False
        for i, a in enumerate(argv):
            if a == '--rename-mode' and i + 1 < len(argv):
                st['mode'] = argv[i + 1].upper()
                changed = True
            elif a in ('--rename-prefix-from', '--rename-tpl-from') and i + 1 < len(argv):
                lines = [ln.strip() for ln in _read_text(argv[i + 1]).splitlines()]
                val = lines[0] if lines else ''
                if a == '--rename-prefix-from':
                    st['prefix'] = val
                    if st['mode'] not in ('A', 'B', 'C'):
                        st['mode'] = 'A'
                else:
                    st['tpl'] = val
                    st['mode'] = 'C'
                changed = True
            elif a == '--rename-order' and i + 1 < len(argv):
                nums = [int(x) for x in re.findall(r'\d+', argv[i + 1])]
                n = len(st['items'])
                if len(nums) != n:
                    print('  ' + paint('顺序要给全：%d 个文件就要 %d 个编号' % (n, n), '1;31'))
                    return 1
                if sorted(nums) != list(range(1, n + 1)):
                    print('  ' + paint('编号要正好是 1 到 %d，不能重复或越界' % n, '1;31'))
                    return 1
                st['order'] = [x - 1 for x in nums]
                changed = True
        if changed:
            _rename_save(st)
        if '--rename-apply' in argv:
            rename_apply(st)
            return 0
        rename_show(st)
        return 0
    if any(a in ('--office-menu',) for a in argv):
        office_menu()
        return 0
    for i, a in enumerate(argv):
        if a == '--office-list' and i + 1 < len(argv):
            office_list(argv[i + 1])
            return 0
        if a == '--office-tip' and i + 2 < len(argv):
            office_tip(argv[i + 1], argv[i + 2])
            return 0
    if any(a in ('--after',) for a in argv):
        print_after_task()
        return 0
    if any(a in ('--wm-menu',) for a in argv):
        print_wm_menu()
        return 0
    if any(a in ('--wm-confirm',) for a in argv):
        print_wm_confirm()
        return 0
    if '--scan-watermark' in argv or '--remove-watermark' in argv:
        targets = [a for a in argv if not a.startswith('--') and os.path.isfile(a)]
        if not targets:
            print('没有收到 PDF 文件。把 PDF 拖进窗口再回车。')
            return 1
        scanning = '--scan-watermark' in argv
        for pdf in targets:
            print('\n[%s]' % os.path.basename(pdf))
            try:
                if scanning:
                    res, info = scan_watermark(pdf, open_preview='--open-preview' in argv)
                    if res is None:
                        print('   跳过：%s' % info)
                        continue
                    if not res.get('cands'):
                        return 1
                else:
                    size, info = remove_watermark(pdf)
                    if size is None:
                        print('   跳过：%s' % info)
                        return 1
                    print('   完成：%.2f MB' % (size / 1048576.0))
            except Exception as exc:
                print('   失败：%s' % exc)
                if os.environ.get('PDFSPLIT_DEBUG'):
                    import traceback
                    traceback.print_exc()
                return 1
        return 0
    if any(a in ('--compress-menu',) for a in argv):
        print_comp_menu()
        return 0
    for i, a in enumerate(argv):
        if a in ('--compress-ready',) and i + 1 < len(argv):
            who = argv[i + 1]
            print(COMP_READY % ('自动（质量 75）' if who.lower() == 'auto'
                                else '%s MB' % who))
            return 0
    if any(a in ('--name-menu',) for a in argv):
        print(NAME_MENU, end='')
        return 0
    if any(a in ('--name-prompt',) for a in argv):
        print(NAME_PROMPT, end='')
        return 0
    for i, a in enumerate(argv):
        if a == '--set-name':
            val = argv[i + 1] if i + 1 < len(argv) else ''
            save_name_template(normalize_tpl(val))
            print()
            banner()
            print('文件名已设置：%s' % describe_template(load_name_template()))
            return 0
        if a.startswith('--set-name='):
            save_name_template(normalize_tpl(a.split('=', 1)[1]))
            print()
            banner()
            print('文件名已设置：%s' % describe_template(load_name_template()))
            return 0
        if a in ('--set-name-from', '--name-from'):
            fn = argv[i + 1] if i + 1 < len(argv) else ''
            lines = [ln.strip() for ln in _read_text(fn).splitlines() if ln.strip()]
            save_name_template(normalize_tpl(lines[0] if lines else ''))
            print()
            banner()
            print('文件名已设置：%s' % describe_template(load_name_template()))
            return 0

    if any(a in ('--menu',) for a in argv):
        print_split_menu()
        return 0
    if any(a in ('--bye',) for a in argv):
        print(BYE_TEXT)
        return 0
    if any(a in ('-h', '--help', '/?') for a in argv):
        print(MENU_TEXT)
        print(NAME_HELP)
        banner()
        return 0
    if any(a in ('-v', '--version') for a in argv):
        banner()
        return 0

    interactive = '--interactive' in argv
    if '--open' in argv:
        open_mode = 'yes'
    elif ('--no-open' in argv or '-nopause' in argv or '--quiet' in argv):
        open_mode = 'no'
    else:
        open_mode = 'ask'
    banner()
    want_jpg = '--pdf-only' not in argv
    want_pdf = '--jpg-only' not in argv
    name_tpl = None
    tpl_given = False
    out_root = None
    compress = '--compress' in argv
    target_mb = None
    args = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('-o', '--out'):
            i += 1
            out_root = argv[i] if i < len(argv) else None
        elif a in ('--target', '-t'):
            i += 1
            raw = argv[i] if i < len(argv) else ''
            if raw and raw.lower() != 'auto':
                try:
                    target_mb = float(raw)
                except ValueError:
                    target_mb = None
        elif a.startswith('--target='):
            raw = a.split('=', 1)[1]
            if raw and raw.lower() != 'auto':
                try:
                    target_mb = float(raw)
                except ValueError:
                    target_mb = None
        elif a in ('--name', '-name'):
            i += 1
            name_tpl = normalize_tpl(argv[i] if i < len(argv) else '')
            tpl_given = True
        elif a.startswith('--name='):
            name_tpl = normalize_tpl(a.split('=', 1)[1])
            tpl_given = True
        elif a in ('--jpg-only', '--pdf-only', '-nopause', '--quiet',
                   '--open', '--no-open', '--compress',
                   '--interactive', '--from-list', '--list'):
            pass
        else:
            args.append(a)
        i += 1
    if name_tpl is not None and not name_tpl.strip():
        name_tpl = None
    if tpl_given:                                 # 这一行是“设置模板”，记住它
        save_name_template(name_tpl or '')
    else:
        name_tpl = load_name_template() or None

    if interactive and not args:
        if tpl_given:
            if name_tpl:
                print('文件名已设置：%s' % describe_template(name_tpl))
                print('之后拖进来的 PDF 都用它；输入 n 回车可以再改。')
            else:
                print('文件名已恢复默认：1组、2组、3组 ……')
        else:
            print('没有收到 PDF 路径。把 PDF 文件（或文件夹）拖进窗口再回车。')
        print_after_task()
        return 0 if tpl_given else 1

    pdfs, roots = collect_pdfs(args, (out_root,))
    if not args:
        pdfs, roots = collect_pdfs([os.getcwd()], (out_root,))
    if not pdfs:
        print('没有找到 PDF 文件。')
        print('用法: 把 PDF（或文件夹）拖到这个 bat 上，或双击后把 PDF 拖进窗口。')
        if interactive:
            print_after_task()
        return 1
    if out_root is None:
        base = os.path.commonpath([os.path.abspath(r) for r in roots]) if len(roots) > 1 \
            else os.path.abspath(roots[0])
        out_root = os.path.join(base, OUT_ROOT_NAME)
    out_root = os.path.abspath(out_root)
    pdfs = [p for p in pdfs if not os.path.abspath(p).startswith(out_root + os.sep)]

    if compress:
        return run_compress(pdfs, target_mb, open_mode, interactive)

    print('输出目录: %s' % out_root)
    if name_tpl:
        print('输出文件名: %s' % describe_template(name_tpl))
    total = 0
    fail = 0
    for pdf in pdfs:
        try:
            made, skipped, folder = process_pdf(pdf, out_root, want_jpg, want_pdf, name_tpl)
            total += len(made)
            print('\n[%s] %d 张 -> %s' % (os.path.basename(pdf), len(made), folder))
            for base_name, page, w, h, changed in made:
                print('   %s.jpg  %s.pdf  第%d页  %dx%d%s'
                      % (base_name, base_name, page, w, h, '  已转正' if changed else ''))
            if skipped:
                print('   已跳过每页重复的模板图 %d 个' % skipped)
        except Exception as exc:
            fail += 1
            print('\n[%s] 处理失败: %s' % (os.path.basename(pdf), exc))
            if os.environ.get('PDFSPLIT_DEBUG'):
                import traceback
                traceback.print_exc()
    print('\n完成：共 %d 张，失败 %d 个文件。' % (total, fail))
    print('%s v%s  ·  作者 %s  ·  GitHub %s'
          % (TITLE, __version__, __author__, __github__))
    ask_open_folder(out_root, open_mode)
    if interactive:
        print_after_task()
    return 0 if fail == 0 else 3


def run_compress(pdfs, target_mb, open_mode='no', interactive=False):
    limit = int(round(target_mb * 1048576)) if target_mb else None
    print('目标大小: %s' % ('%.2f MB' % target_mb if target_mb else '自动'))
    ok = 0
    fail = 0
    first_out = None
    for pdf in pdfs:
        print('\n[%s]' % os.path.basename(pdf))
        try:
            size, info = compress_file(pdf, limit)
        except Exception as exc:
            size, info = None, '压缩失败: %s' % exc
            if os.environ.get('PDFSPLIT_DEBUG'):
                import traceback
                traceback.print_exc()
        if size is None:
            fail += 1
            print('   跳过：%s' % info)
        else:
            ok += 1
            if first_out is None:
                first_out = os.path.dirname(info)
    print('\n完成：压缩 %d 个，跳过 %d 个。' % (ok, fail))
    print('%s v%s  ·  作者 %s  ·  GitHub %s'
          % (TITLE, __version__, __author__, __github__))
    if first_out and open_mode != 'no':
        ask_open_folder(first_out, open_mode)
    if interactive:
        print_after_task()
    return 0 if fail == 0 else 3


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
::#<<<PY
rem  ------------------------------------------------------------------------
rem   拆分PDF图片 v2.0   作者: 小楠三岁   GitHub: https://github.com/xiaonansansui
rem   以上是这个 bat 自带的 Python 程序；下面这段只是署名备注，运行不到。
rem  ------------------------------------------------------------------------
