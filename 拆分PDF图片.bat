@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>nul
title PDF page splitter v2.3 - by XiaoNanSanSui @xiaonansansui

rem ===========================================================================
rem  PDF page splitter  v2.3
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
if "%PICK%"=="0" goto :cleanup
if not defined PICK goto :cleanup
echo [i] please type 1, 2 or 0
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

rem ---- 6. interactive loop: the window never closes by itself ----------------
:ask
set "LINE="
set /p "LINE=PDF: "
if not defined LINE goto :ask_empty
if /i "%LINE%"=="q" goto :cleanup
if /i "%LINE%"=="quit" goto :cleanup
if /i "%LINE%"=="exit" goto :cleanup
if "%LINE%"=="0" goto :home
if "%LINE%"=="." goto :run_here
if /i "%LINE%"=="n" if "%MODEOPT%"=="" goto :namewiz

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
echo [i] please type 1, 2, 3 or 0
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
echo   PDF page splitter v2.3   -   XiaoNanSanSui (xiaonansansui)
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
版本   : 2.3

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
import os
import re
import shlex
import sys
import tempfile
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
__version__ = '2.3'

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
   拆分PDF图片 v2.3    ·    作者: 小楠三岁    ·    @xiaonansansui
  ================================================================
     1   拆分 PDF      每页的大图拆成 jpg，并生成同名 A4 PDF
     2   压缩 PDF      把 PDF 压到你要的大小（比如 5 MB）
     0   退出
  ================================================================
   请选择 1 / 2（输入 0 退出）: '''

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


# ---------- 记住上一次用过的文件名模板 ----------

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
                lm = re.search(rb'/Length\s+(\d+)', body)
                cut = int(lm.group(1)) if lm else len(raw)
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
    return os.path.getsize(out_path), 'ok'


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
        print()
        print(HOME_TEXT, end='')
        return 0
    if any(a in ('--compress-menu',) for a in argv):
        print(COMP_MENU, end='')
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
        print()
        print(MENU_TEXT)
        print('   当前输出文件名：%s' % describe_template(load_name_template()))
        print()
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
        print(END_HINT)
        return 0 if tpl_given else 1

    pdfs, roots = collect_pdfs(args, (out_root,))
    if not args:
        pdfs, roots = collect_pdfs([os.getcwd()], (out_root,))
    if not pdfs:
        print('没有找到 PDF 文件。')
        print('用法: 把 PDF（或文件夹）拖到这个 bat 上，或双击后把 PDF 拖进窗口。')
        if interactive:
            print(END_HINT)
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
        print(END_HINT)
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
        print(END_HINT)
    return 0 if fail == 0 else 3


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
::#<<<PY
rem  ------------------------------------------------------------------------
rem   拆分PDF图片 v2.0   作者: 小楠三岁   GitHub: https://github.com/xiaonansansui
rem   以上是这个 bat 自带的 Python 程序；下面这段只是署名备注，运行不到。
rem  ------------------------------------------------------------------------