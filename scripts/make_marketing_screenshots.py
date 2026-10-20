#!/usr/bin/env python3
"""마케팅 스크린샷 목업 생성: HTML 생성 → 헤드리스 Chrome 렌더링.

슬라이드마다 layout 이 달라 배치가 다양함:
  hero-bleed  : 헤드라인 상단 중앙 + 정면 대형 폰, 하단 블리드
  left-text   : 좌측 정렬 텍스트 + 오른쪽으로 기운 폰
  text-bottom : 폰 상단 + 텍스트 하단
  flat-rotate : 평면 회전(-5°) 폰, 하단 블리드
  dark        : 다크 배경 반전 + 정면 폰
"""
import subprocess, sys, pathlib

# 사용법: 이 파일을 프로젝트 scripts/ 로 복사한 뒤 SRC, W/H, SHOTS 를 수정하고 실행
SRC = pathlib.Path.cwd() / "docs" / "screenshots"   # 원본 스크린샷 폴더 (프로젝트에 맞게 수정)
OUT = SRC / "marketing"
WORK = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688   # App Store Connect 제출 규격

SHOTS = [
    ("01-feed.png",     "hero-bleed",  "먹은 순간을 톡, 사진으로", "빈 칸 없이 쌓이는 나만의 식사 일기"),
    ("02-detail.png",   "left-text",   "한 끼 한 끼<br>또렷하게", "시간과 메모까지 함께 남아요"),
    ("03-stats.png",    "text-bottom", "한 끼만 남겨도 이어져요", "놓친 날이 있어도 기록은 줄지 않아요"),
    ("04-settings.png", "dark",        "챙길 식사만 알려드려요", "내 생활에 맞춘 식사 알림"),
]

# 언어별 문구. 한국어는 위 SHOTS 그대로(원본 docs/screenshots/ → marketing/ko/),
# 다른 언어는 원본 docs/screenshots/raw/<언어>/ → marketing/<언어>/.
# 사용법: python3 scripts/make_marketing_screenshots.py [--lang en] [파일이름]
SHOTS_BY_LANG = {
    "ko": SHOTS,
    "en": [
        ("01-feed.png",     "hero-bleed",  "Snap it as you eat", "A meal diary that fills itself in"),
        ("02-detail.png",   "left-text",   "Every meal,<br>in focus", "With the time and your notes"),
        ("03-stats.png",    "text-bottom", "One meal keeps it going", "Miss a day, keep your progress"),
        ("04-settings.png", "dark",        "Make it yours", "Choose what you log and what you see"),
    ],
}

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:#f4f4f5; font-family:-apple-system, "Apple SD Gothic Neo", sans-serif; position:relative; }}
.headline {{ font-size:100px; font-weight:800; color:#141416; letter-spacing:-2px; line-height:1.25; }}
.sub {{ font-size:52px; font-weight:500; color:#9a9aa0; letter-spacing:-1px; }}
.phone {{ background:#17171a; border-radius:116px; border:3px solid #3a3a3e; padding:25px;
  box-shadow: 60px 90px 120px rgba(0,0,0,.28), 20px 30px 50px rgba(0,0,0,.18); }}
.phone img {{ width:100%; display:block; border-radius:92px; }}
"""

LAYOUTS = {
    # 1) 정면 대형, 하단 블리드
    "hero-bleed": """
.headline { text-align:center; margin-top:290px; padding:0 70px; }
.sub { text-align:center; margin-top:52px; }
.wrap { display:flex; justify-content:center; margin-top:150px; }
.phone { width:1000px; }
""",
    # 2) 좌측 정렬 텍스트 + 오른쪽 기울기, 오른쪽 블리드
    "left-text": """
.headline { text-align:left; margin:300px 0 0 110px; }
.sub { text-align:left; margin:48px 0 0 114px; }
.wrap { perspective:2600px; perspective-origin:30% 30%; position:absolute; left:300px; top:990px; }
.phone { width:840px; transform:rotateY(16deg) rotateX(2deg); }
""",
    # 3) 폰 상단, 텍스트 하단
    "text-bottom": """
.wrap { perspective:2800px; perspective-origin:50% 40%; display:flex; justify-content:center; margin-top:170px; }
.phone { width:880px; transform:rotateY(-10deg) rotateX(2deg); }
.headline { text-align:center; margin-top:120px; padding:0 70px; }
.sub { text-align:center; margin-top:48px; }
""",
    # 4) 평면 회전, 좌측 치우침 + 하단 블리드
    "flat-rotate": """
.headline { text-align:center; margin-top:270px; padding:0 70px; }
.sub { text-align:center; margin-top:52px; }
.wrap { position:absolute; left:120px; top:1010px; }
.phone { width:1010px; transform:rotate(-6deg); }
""",
    # 5) 다크 배경 반전 + 정면
    "dark": """
body { background:#131316; }
.headline { color:#f5f5f7; text-align:center; margin-top:290px; padding:0 70px; }
.sub { color:#77777d; text-align:center; margin-top:52px; }
.wrap { display:flex; justify-content:center; margin-top:150px; }
.phone { width:930px; border-color:#48484e;
  box-shadow: 0 0 160px rgba(80,140,255,.22), 40px 70px 110px rgba(0,0,0,.55); }
""",
}

# text-bottom 은 폰이 먼저 오는 DOM 순서
BODY_TEXT_FIRST = '<div class="headline">{headline}</div><div class="sub">{sub}</div><div class="wrap"><div class="phone"><img src="{img}"></div></div>'
BODY_PHONE_FIRST = '<div class="wrap"><div class="phone"><img src="{img}"></div></div><div class="headline">{headline}</div><div class="sub">{sub}</div>'

HTML = """<!doctype html><html><head><meta charset="utf-8"><style>
{base}{layout}
</style></head><body>{body}</body></html>"""

def main(only=None, lang="ko"):
    src = SRC if lang == "ko" else SRC / "raw" / lang
    out = OUT / lang  # marketing/<언어>/ — 언어 폴더가 있으면 DeployBar 가 언어별로 올린다
    out.mkdir(parents=True, exist_ok=True)
    for fname, layout, headline, sub in SHOTS_BY_LANG[lang]:
        if only and fname != only:
            continue
        body_tpl = BODY_PHONE_FIRST if layout == "text-bottom" else BODY_TEXT_FIRST
        body = body_tpl.format(headline=headline, sub=sub, img=(src / fname).as_uri())
        html_path = WORK / (fname.replace(".png", ".html") if lang == "ko" else f"{lang}-" + fname.replace(".png", ".html"))
        html_path.write_text(HTML.format(base=BASE_CSS, layout=LAYOUTS[layout], body=body), encoding="utf-8")
        out_png = out / fname
        subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                        f"--window-size={W},{H}", "--force-device-scale-factor=1",
                        "--hide-scrollbars", "--disable-gpu", html_path.as_uri()],
                       check=True, capture_output=True)
        print(f"rendered {out_png}")

if __name__ == "__main__":
    args = sys.argv[1:]
    lang = "ko"
    if "--lang" in args:
        i = args.index("--lang"); lang = args[i + 1]; del args[i:i + 2]
    main(args[0] if args else None, lang)
