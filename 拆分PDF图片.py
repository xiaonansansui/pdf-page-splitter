# -*- coding: utf-8 -*-
"""拆分PDF图片 —— 把 PDF 里每页的大图拆出来，存成 N组.jpg，并生成同名 A4 PDF。

作者   : 小楠三岁
GitHub : https://github.com/xiaonansansui
版本   : 2.1

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
__version__ = '2.1'

OUT_ROOT_NAME = '拆分图片'
A4_SHORT, A4_LONG = 595.28, 841.89   # A4 短边/长边（pt）
MARGIN = 14.0

MENU_TEXT = '''
  ================================================================
   拆分PDF图片 v2.1    ·    作者: 小楠三岁    ·    @xiaonansansui
  ================================================================
   把 PDF 文件（或文件夹）直接拖进这个窗口，然后回车
   可以一次拖多个；直接回车 = 处理本程序所在目录
   处理完会问要不要打开保存目录（回车 = 不打开）
   输入 q 回车 = 退出     （窗口不会自己关，拖文件也不会关）
  ----------------------------------------------------------------
   想自定义输出文件名：单独输入一行
       --name 会议纪要-{n}
   之后拖进来的文件都会用这个模板；输入 --name 回车恢复默认。
   占位符：{n} 序号   {nn} 两位补零   {page} 原页码
           {pdf} 原文件名   {date} 今天日期
  ================================================================
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
    if any(a in ('--menu',) for a in argv):
        print()
        print(MENU_TEXT)
        saved = load_name_template()
        if saved:
            print('   当前文件名模板: %s' % saved)
            print('   想恢复默认（1组、2组 ……）就单独输入一行  --name')
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
    args = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ('-o', '--out'):
            i += 1
            out_root = argv[i] if i < len(argv) else None
        elif a in ('--name', '-name'):
            i += 1
            name_tpl = argv[i] if i < len(argv) else None
            tpl_given = True
        elif a.startswith('--name='):
            name_tpl = a.split('=', 1)[1]
            tpl_given = True
        elif a in ('--jpg-only', '--pdf-only', '-nopause', '--quiet',
                   '--open', '--no-open',
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
                print('已保存文件名模板: %s' % name_tpl)
                print('之后拖进来的 PDF 都用它；单独输入一行 --name 可恢复默认。')
            else:
                print('已恢复默认文件名：1组、2组、3组 ……')
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

    print('输出目录: %s' % out_root)
    if name_tpl:
        print('文件名模板: %s' % name_tpl)
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


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
