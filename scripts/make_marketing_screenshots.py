#!/usr/bin/env python3
"""마케팅 스크린샷 목업 생성: HTML 생성 → 헤드리스 Chrome 렌더링.

슬라이드마다 layout 이 달라 배치가 다양함:
  hero-bleed  : 헤드라인 상단 중앙 + 정면 대형 폰, 하단 블리드
  left-text   : 좌측 정렬 텍스트 + 오른쪽으로 기운 폰
  text-bottom : 폰 상단 + 텍스트 하단
  flat-rotate : 평면 회전(-5°) 폰, 하단 블리드
  dark        : 다크 배경 반전 + 정면 폰
"""
import subprocess, sys, pathlib, tempfile

# 사용법: 이 파일을 프로젝트 scripts/ 로 복사한 뒤 SRC, W/H, SHOTS 를 수정하고 실행
SRC = pathlib.Path.cwd() / "docs" / "screenshots"   # 원본 스크린샷 폴더 (프로젝트에 맞게 수정)
OUT = SRC / "marketing"
WORK = pathlib.Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# 사용자 Chrome · 다른 렌더와 프로필이 겹치면 headless 가 멈춘다. 장마다 새 프로필을 쓴다.
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
    "zh-Hans": [
        ("01-feed.png", "hero-bleed", "吃饭时<br>随手一拍", "一张张照片，攒成你的饮食日记"),
        ("02-detail.png", "left-text", "每一餐<br>都清清楚楚", "时间和备注一起留下"),
        ("03-stats.png", "text-bottom", "记一餐也算数", "漏了一天，记录也不会清零"),
        ("04-settings.png", "dark", "按你的习惯来", "想记什么、看什么，你说了算"),
    ],
    "zh-Hant": [
        ("01-feed.png", "hero-bleed", "吃飯時<br>隨手拍一張", "一張張照片，累積成你的飲食日記"),
        ("02-detail.png", "left-text", "每一餐<br>都清清楚楚", "時間和備註一起留下"),
        ("03-stats.png", "text-bottom", "記一餐也算數", "漏了一天，紀錄也不會歸零"),
        ("04-settings.png", "dark", "照你的習慣來", "想記什麼、看什麼，由你決定"),
    ],
    "ja": [
        ("01-feed.png", "hero-bleed", "食べたら<br>パシャッと記録", "写真がそのまま食事日記に"),
        ("02-detail.png", "left-text", "一食ずつ<br>くっきり", "時間もメモも一緒に残せます"),
        ("03-stats.png", "text-bottom", "一食だけでも<br>続けられる", "休んだ日があっても記録は減りません"),
        ("04-settings.png", "dark", "自分好みに", "記録する内容も表示も選べます"),
    ],
    "ru": [
        ("01-feed.png", "hero-bleed", "Сфотографируй<br>свою еду", "Дневник питания, который ведётся сам"),
        ("02-detail.png", "left-text", "Каждый приём<br>пищи — чётко", "Со временем и заметками"),
        ("03-stats.png", "text-bottom", "Хватит одного<br>приёма пищи", "Пропустили день — прогресс сохранится"),
        ("04-settings.png", "dark", "Под себя", "Выберите, что записывать и что видеть"),
    ],
    "es": [
        ("01-feed.png", "hero-bleed", "Una foto<br>al comer", "Un diario de comidas que se llena solo"),
        ("02-detail.png", "left-text", "Cada comida,<br>con detalle", "Con la hora y tus notas"),
        ("03-stats.png", "text-bottom", "Con una comida,<br>sigues en racha", "Si fallas un día, no pierdes lo logrado"),
        ("04-settings.png", "dark", "A tu manera", "Elige qué registrar y qué ver"),
    ],
    "de": [
        ("01-feed.png", "hero-bleed", "Einfach knipsen,<br>wenn du isst", "Ein Essenstagebuch, das sich selbst füllt"),
        ("02-detail.png", "left-text", "Jede Mahlzeit<br>im Blick", "Mit Uhrzeit und Notizen"),
        ("03-stats.png", "text-bottom", "Eine Mahlzeit<br>reicht schon", "Ein Tag Pause? Dein Fortschritt bleibt"),
        ("04-settings.png", "dark", "Ganz nach<br>deinem Geschmack", "Wähle, was du einträgst und siehst"),
    ],
    "fr": [
        ("01-feed.png", "hero-bleed", "Une photo<br>à chaque repas", "Un journal de repas qui se remplit seul"),
        ("02-detail.png", "left-text", "Chaque repas,<br>en détail", "Avec l’heure et vos notes"),
        ("03-stats.png", "text-bottom", "Un repas suffit<br>à continuer", "Un jour manqué n’efface pas vos progrès"),
        ("04-settings.png", "dark", "À votre goût", "Choisissez quoi noter et quoi afficher"),
    ],
    "it": [
        ("01-feed.png", "hero-bleed", "Scatta<br>mentre mangi", "Un diario dei pasti che si scrive da solo"),
        ("02-detail.png", "left-text", "Ogni pasto,<br>nei dettagli", "Con l’ora e le tue note"),
        ("03-stats.png", "text-bottom", "Basta un pasto<br>per continuare", "Salti un giorno? I progressi restano"),
        ("04-settings.png", "dark", "A modo tuo", "Scegli cosa registrare e cosa vedere"),
    ],
    "pt-BR": [
        ("01-feed.png", "hero-bleed", "Uma foto<br>na hora de comer", "Um diário alimentar que se monta sozinho"),
        ("02-detail.png", "left-text", "Cada refeição<br>em detalhes", "Com horário e suas anotações"),
        ("03-stats.png", "text-bottom", "Uma refeição<br>já conta", "Pulou um dia? Seu progresso continua"),
        ("04-settings.png", "dark", "Do seu jeito", "Escolha o que registrar e o que ver"),
    ],
    "th": [
        ("01-feed.png", "hero-bleed", "กินปุ๊บ<br>ถ่ายปั๊บ", "ไดอารี่อาหารที่เต็มขึ้นเองทีละรูป"),
        ("02-detail.png", "left-text", "ทุกมื้อ<br>ชัดเจน", "พร้อมเวลาและบันทึกย่อ"),
        ("03-stats.png", "text-bottom", "มื้อเดียว<br>ก็นับต่อได้", "พลาดไปวันหนึ่ง สถิติก็ไม่หาย"),
        ("04-settings.png", "dark", "ปรับให้เป็นแบบคุณ", "เลือกเองว่าจะบันทึกและดูอะไร"),
    ],
    "vi": [
        ("01-feed.png", "hero-bleed", "Chụp một tấm<br>khi vừa ăn", "Nhật ký bữa ăn tự đầy lên từng ngày"),
        ("02-detail.png", "left-text", "Từng bữa<br>rõ ràng", "Kèm giờ ăn và ghi chú"),
        ("03-stats.png", "text-bottom", "Một bữa<br>cũng tính", "Lỡ một ngày, tiến độ vẫn còn"),
        ("04-settings.png", "dark", "Theo cách của bạn", "Chọn ghi gì và xem gì"),
    ],
    "cs": [
        ("01-feed.png", "hero-bleed", "Vyfoť jídlo,<br>když jíš", "Jídelní deník, který se plní sám"),
        ("02-detail.png", "left-text", "Každé jídlo<br>přehledně", "Včetně času a poznámek"),
        ("03-stats.png", "text-bottom", "Stačí jedno<br>jídlo denně", "Vynechaný den ti pokrok nevezme"),
        ("04-settings.png", "dark", "Podle tebe", "Vyber si, co zapisovat a co vidět"),
    ],
    "da": [
        ("01-feed.png", "hero-bleed", "Knips maden,<br>mens du spiser", "En maddagbog, der fylder sig selv"),
        ("02-detail.png", "left-text", "Hvert måltid<br>helt tydeligt", "Med tidspunkt og noter"),
        ("03-stats.png", "text-bottom", "Ét måltid<br>holder det kørende", "Spring en dag over uden at miste noget"),
        ("04-settings.png", "dark", "Gør den til din", "Vælg, hvad du logger og ser"),
    ],
    "el": [
        ("01-feed.png", "hero-bleed", "Τράβα μια φωτο<br>όταν τρως", "Ένα ημερολόγιο γευμάτων που γεμίζει μόνο του"),
        ("02-detail.png", "left-text", "Κάθε γεύμα<br>καθαρά", "Με την ώρα και τις σημειώσεις σου"),
        ("03-stats.png", "text-bottom", "Ένα γεύμα<br>φτάνει", "Έχασες μια μέρα; Η πρόοδος μένει"),
        ("04-settings.png", "dark", "Όπως σου αρέσει", "Διάλεξε τι καταγράφεις και τι βλέπεις"),
    ],
    "fi": [
        ("01-feed.png", "hero-bleed", "Ota kuva,<br>kun syöt", "Ruokapäiväkirja, joka täyttyy itsestään"),
        ("02-detail.png", "left-text", "Jokainen ateria<br>selkeästi", "Kellonajan ja muistiinpanojen kanssa"),
        ("03-stats.png", "text-bottom", "Yksikin ateria<br>riittää", "Väliin jäänyt päivä ei vie edistystä"),
        ("04-settings.png", "dark", "Omanlaisesi", "Valitse, mitä kirjaat ja mitä näet"),
    ],
    "id": [
        ("01-feed.png", "hero-bleed", "Foto saat<br>kamu makan", "Diari makan yang terisi sendiri"),
        ("02-detail.png", "left-text", "Setiap makan,<br>jelas tercatat", "Lengkap dengan jam dan catatan"),
        ("03-stats.png", "text-bottom", "Satu kali makan<br>pun dihitung", "Terlewat sehari, progres tetap aman"),
        ("04-settings.png", "dark", "Sesuai gayamu", "Pilih apa yang dicatat dan ditampilkan"),
    ],
    "nb": [
        ("01-feed.png", "hero-bleed", "Ta et bilde<br>når du spiser", "En matdagbok som fyller seg selv"),
        ("02-detail.png", "left-text", "Hvert måltid<br>helt tydelig", "Med klokkeslett og notater"),
        ("03-stats.png", "text-bottom", "Ett måltid<br>holder det gående", "Hopp over en dag uten å miste noe"),
        ("04-settings.png", "dark", "Gjør den til din", "Velg hva du logger og ser"),
    ],
    "nl": [
        ("01-feed.png", "hero-bleed", "Maak een foto<br>als je eet", "Een eetdagboek dat zichzelf vult"),
        ("02-detail.png", "left-text", "Elke maaltijd<br>helder in beeld", "Met tijd en notities"),
        ("03-stats.png", "text-bottom", "Eén maaltijd<br>is genoeg", "Dag gemist? Je voortgang blijft"),
        ("04-settings.png", "dark", "Helemaal van jou", "Kies wat je bijhoudt en wat je ziet"),
    ],
    "pl": [
        ("01-feed.png", "hero-bleed", "Zrób zdjęcie,<br>gdy jesz", "Dziennik posiłków, który wypełnia się sam"),
        ("02-detail.png", "left-text", "Każdy posiłek<br>w szczegółach", "Z godziną i notatkami"),
        ("03-stats.png", "text-bottom", "Wystarczy<br>jeden posiłek", "Opuszczony dzień nie zabiera postępów"),
        ("04-settings.png", "dark", "Po swojemu", "Wybierz, co zapisujesz i co widzisz"),
    ],
    "sv": [
        ("01-feed.png", "hero-bleed", "Ta en bild<br>när du äter", "En matdagbok som fyller sig själv"),
        ("02-detail.png", "left-text", "Varje måltid<br>tydligt", "Med klockslag och anteckningar"),
        ("03-stats.png", "text-bottom", "En måltid<br>räcker", "Missa en dag utan att tappa något"),
        ("04-settings.png", "dark", "Gör den till din", "Välj vad du loggar och ser"),
    ],
    "tr": [
        ("01-feed.png", "hero-bleed", "Yerken<br>bir fotoğraf çek", "Kendiliğinden dolan bir yemek günlüğü"),
        ("02-detail.png", "left-text", "Her öğün<br>net biçimde", "Saat ve notlarınla birlikte"),
        ("03-stats.png", "text-bottom", "Tek öğün<br>bile yeter", "Bir gün kaçırsan da ilerlemen kalır"),
        ("04-settings.png", "dark", "Tam sana göre", "Neyi kaydedeceğini ve göreceğini seç"),
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
        # 바쁜 기계에선 headless Chrome 이 가끔 실패한다 — 몇 번 더 시도한다
        for attempt in range(4):
            out_png.unlink(missing_ok=True)
            try:
                r = subprocess.run([CHROME, "--headless=new", f"--screenshot={out_png}",
                                    f"--window-size={W},{H}", "--force-device-scale-factor=1",
                                    "--hide-scrollbars", "--disable-gpu",
                                    f"--user-data-dir={tempfile.mkdtemp(prefix='sekki-marketing-chrome-')}",
                                    html_path.as_uri()],
                                   capture_output=True, timeout=400)
            except subprocess.TimeoutExpired:
                continue
            # 그림을 다 쓴 뒤 종료 단계에서 Chrome 이 비정상 코드로 끝나는 일이 있다 — 파일이 생겼으면 성공으로 본다
            if out_png.exists() and out_png.stat().st_size > 0:
                break
        else:
            raise SystemExit(f"Chrome 이 그리지 못했다: {out_png}")
        print(f"rendered {out_png}")

if __name__ == "__main__":
    args = sys.argv[1:]
    lang = "ko"
    if "--lang" in args:
        i = args.index("--lang"); lang = args[i + 1]; del args[i:i + 2]
    main(args[0] if args else None, lang)
