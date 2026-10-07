#!/usr/bin/env python3
"""App Store 크리에이티브 자산(제품 페이지 헤더 · 검색 결과) 생성: HTML → 헤드리스 Chrome.

사용법: python3 scripts/make_creative_assets.py [언어 ...]     (없으면 전부)

자리
  docs/screenshots/creative/<스토어 로케일>/header.png   3840x1646  제품 페이지 맨 위
  docs/screenshots/creative/<스토어 로케일>/search.png   3840x2560  검색 결과 (없으면 스크린샷이 대신 보인다)

⚠️ 안전 영역 밖은 기기에 따라 잘린다. 글은 **반드시** 안전 영역 안에 둔다(배경 · 기기 그림은 넘쳐도 된다).
   수치는 Apple 공식 PSD 템플릿에서 잰 값이다(https://developer.apple.com/app-store/asset-best-practices/).
   아이폰에서 헤더는 가운데만 남고, 검색 결과는 약 385pt 폭으로 줄어 보인다. 그래서 글이 크다.

⚠️ 가격 · 할인 · 주소(URL) · 수상 · 다른 플랫폼 이름은 넣지 않는다(Apple 가이드).

기기 화면은 docs/screenshots/0N-*.png 시뮬레이터 원본(make_marketing_screenshots.py 와 같은 것)을 쓴다.
스토어 언어는 한국어 하나다(deploy.env LOCALES=ko).
"""
import shutil, subprocess, sys, pathlib, tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "screenshots" / "creative"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# 다른 Chrome(사용자 창 · 다른 렌더링)과 프로필이 겹치면 headless 가 멈춘다. 따로 쓴다.
PROFILE = pathlib.Path(tempfile.gettempdir()) / "sekki-creative-chrome"

# 앱 언어 → App Store Connect 로케일
STORE = {}

# (가로, 세로, 안전 영역 left, top, right, bottom)
SPEC = {
    "header": (3840, 1646, (1097, 493, 2743, 1154)),
    "search": (3840, 2560, (836, 765, 3004, 1795)),
}

# 검색 결과는 스크린샷 1장("먹은 순간을 톡, 사진으로")과 **같은 이야기**다.
# 눈썹글은 검색창에 칠 말이다.
SEARCH = {
    "ko": ("식단 일기", "먹은 순간을<br>톡, 사진으로", "빈 칸 없이 쌓이는 나만의 식사 일기"),
}

# 헤더는 한 가지 약속만: 사진 한 장이면 하루 세끼가 기록된다.
HEADER = {
    "ko": ("세끼 식단 기록", "사진 한 장이면<br>오늘 세끼가 남아요"),
}

# ⚠️ 바탕 · 글자색은 마케팅 스크린샷(make_marketing_screenshots.py)과 같다: 밝은 회색 바탕, 검은 헤드라인,
#    회색 보조문, 검은 기기. 눈썹글은 앱의 기록 버튼 파랑.
BASE_CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
html,body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; }
body { background:#f4f4f5; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", sans-serif; }
.glow { position:absolute; border-radius:50%%; filter:blur(170px); pointer-events:none; }
.text { position:absolute; display:flex; flex-direction:column; justify-content:center; }
.eyebrow { font-weight:700; color:#0A7CFF; letter-spacing:-0.01em; line-height:1.15; }
.headline { font-weight:800; color:#141416; letter-spacing:-0.03em; line-height:1.15; text-wrap:balance; }
.sub { font-weight:500; color:#8e8e94; letter-spacing:-0.01em; line-height:1.35; text-wrap:balance; }
:lang(ko) .headline, :lang(ko) .sub, :lang(ko) .eyebrow { word-break:keep-all; }
.phone { position:absolute; background:#17171a; border:6px solid #3a3a3e; padding:40px; border-radius:190px;
  box-shadow: 60px 90px 160px rgba(0,0,0,.24), 20px 30px 60px rgba(0,0,0,.14); }
.phone img { width:100%%; display:block; border-radius:152px; }
.photo { position:absolute; border-radius:56px; object-fit:cover; box-shadow: 30px 40px 90px rgba(0,0,0,.18); }
"""

# 글이 상자를 넘지 않을 때까지 줄인다. 끝까지 안 맞으면 표시하고 멈춘다. (고치지 않는다)
FIT_JS = """
<script>
function lines(el) {
  return Math.round(el.getBoundingClientRect().height / parseFloat(getComputedStyle(el).lineHeight));
}
function fit(box, el, max, min) {
  const want = el.querySelectorAll('br').length + 1;
  let size = max;
  el.style.fontSize = size + 'px';
  while (size > min && (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 ||
         lines(el) > want)) {
    size -= 4; el.style.fontSize = size + 'px';
  }
  if (box.scrollHeight > box.clientHeight + 1 || box.scrollWidth > box.clientWidth + 1 || lines(el) > want)
    document.body.dataset.overflow = '1';
}
document.fonts.ready.then(() => {
  const box = document.querySelector('.text');
  const h = document.querySelector('.headline');
  fit(box, h, +h.dataset.max, +h.dataset.min);
  document.body.dataset.done = '1';
});
</script>
"""


def chrome(args, until, timeout=900):
    """headless Chrome 을 돌리고, 결과가 나오면 끝내기를 기다리지 않고 닫는다.
    ⚠️ 기계가 바쁘면 Chrome 이 결과를 낸 뒤에도 몇 분씩 안 끝난다."""
    import time
    log = pathlib.Path(tempfile.mkstemp(prefix="sekki-chrome-", suffix=".log")[1])
    with open(log, "w") as fh:
        p = subprocess.Popen([CHROME, "--headless=new", f"--user-data-dir={PROFILE}", *args],
                             stdout=fh, stderr=subprocess.STDOUT, text=True)
        start = time.time()
        while time.time() - start < timeout:
            out = log.read_text(errors="ignore")
            if until(out):
                time.sleep(1)
                break
            if p.poll() is not None:
                break
            time.sleep(1)
        out = log.read_text(errors="ignore")
        if p.poll() is None:
            p.kill(); p.wait()
    log.unlink(missing_ok=True)
    return out


def shot(lang, name):
    return (ROOT / "docs" / "screenshots" / name).as_uri()


def phone(img, left, top, width, rotate=0):
    return (f'<div class="phone" style="left:{left}px;top:{top}px;width:{width}px;'
            f'transform:rotate({rotate}deg)"><img src="{img}"></div>')


def search_html(lang):
    W, H, (l, t, r, b) = SPEC["search"]
    eyebrow, headline, sub = SEARCH[lang]
    sw, sh = r - l, b - t
    col = int(sw * 0.58)
    ph_w = 1000
    ph_left = l + col + int(sw * 0.03)
    return f"""
<div class="glow" style="left:{ph_left - 250}px;top:700px;width:1600px;height:1600px;background:rgba(255,170,60,.22)"></div>
<div class="glow" style="left:{l - 700}px;top:{t - 500}px;width:1400px;height:1000px;background:rgba(10,124,255,.07)"></div>
{phone(shot(lang, "01-feed.png"), ph_left, t - 360, ph_w, 0)}
<div class="text" style="left:{l}px;top:{t}px;width:{col}px;height:{sh}px">
  <div class="eyebrow" style="font-size:92px">{eyebrow}</div>
  <div class="headline" data-max="220" data-min="120" style="margin-top:36px">{headline}</div>
  <div class="sub" style="font-size:80px;margin-top:52px">{sub}</div>
</div>"""


def header_html(lang):
    W, H, (l, t, r, b) = SPEC["header"]
    eyebrow, headline = HEADER[lang]
    sw, sh = r - l, b - t
    # 앱에 실제로 쓰인 음식 사진(docs/screenshots/seed)을 안전 영역 바깥에 흩는다(잘려도 되는 장식).
    seed = ROOT / "docs" / "screenshots" / "seed"
    photos = [("03.jpg", 1000, 70, 300, -8), ("05.jpg", 1010, 1250, 260, 10),
              ("07.jpg", 2560, 40, 280, 7), ("09.jpg", 2600, 1260, 300, -6)]
    photos_html = "".join(f'<img class="photo" src="{(seed / f).as_uri()}" style="left:{x}px;top:{y}px;width:{w}px;'
                          f'height:{w}px;transform:rotate({rot}deg)">' for f, x, y, w, rot in photos)
    return f"""
<div class="glow" style="left:{l - 200}px;top:{t - 400}px;width:{sw + 400}px;height:{sh + 800}px;background:rgba(255,170,60,.14)"></div>
{photos_html}
{phone(shot(lang, "01-feed.png"), 300, 360, 640, -9)}
{phone(shot(lang, "02-detail.png"), 2900, 360, 640, 9)}
<div class="text" style="left:{l}px;top:{t}px;width:{sw}px;height:{sh}px;align-items:center;text-align:center">
  <div class="eyebrow" style="font-size:76px">{eyebrow}</div>
  <div class="headline" data-max="200" data-min="110" style="margin-top:22px">{headline}</div>
</div>"""


def render(lang, kind):
    W, H, _ = SPEC[kind]
    body = search_html(lang) if kind == "search" else header_html(lang)
    page = (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>'
            f'{BASE_CSS % {"W": W, "H": H}}</style></head><body>{body}{FIT_JS}</body></html>')
    html_path = pathlib.Path(tempfile.gettempdir()) / f"sekki-creative-{lang}-{kind}.html"
    html_path.write_text(page, encoding="utf-8")
    dom = chrome(["--dump-dom", f"--window-size={W},{H}", "--force-device-scale-factor=1", "--disable-gpu",
                  "--virtual-time-budget=3000", html_path.as_uri()], until=lambda out: "</html>" in out)
    if 'data-done="1"' not in dom:
        raise SystemExit(f"글 맞추기가 끝나지 않았다: {lang} {kind}")
    if 'data-overflow="1"' in dom:
        raise SystemExit(f"글이 안전 영역을 넘는다: {lang} {kind} - 문구를 줄일 것")
    locales = STORE.get(lang, [lang])
    out_dir = OUT / locales[0]
    out_dir.mkdir(parents=True, exist_ok=True)
    out_png = out_dir / f"{kind}.png"
    out_png.unlink(missing_ok=True)
    chrome([f"--screenshot={out_png}", f"--window-size={W},{H}", "--force-device-scale-factor=1",
            "--hide-scrollbars", "--disable-gpu", "--virtual-time-budget=3000",
            "--allow-file-access-from-files", html_path.as_uri()],
           until=lambda out: out_png.exists() and out_png.stat().st_size > 0 and "written" in out)
    if not out_png.exists() or out_png.stat().st_size == 0:
        raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
    print(f"rendered {out_png}")
    for extra in locales[1:]:
        (OUT / extra).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(out_png, OUT / extra / out_png.name)


if __name__ == "__main__":
    langs = sys.argv[1:] or list(SEARCH)
    for lang in langs:
        if lang not in SEARCH:
            raise SystemExit(f"모르는 언어: {lang} (아는 것: {', '.join(SEARCH)})")
        for kind in ("header", "search"):
            render(lang, kind)
