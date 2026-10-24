#!/usr/bin/env python3
"""App Store 마케팅 스크린샷: HTML → 헤드리스 Chrome (appstore-assets 스킬의 스크립트를 이 앱에 맞춘 것).

사용법: python3 scripts/make_marketing_screenshots.py [스토어로케일 ...]   (없으면 전부)

원본   docs/screenshots/raw/<앱언어>/0N-….png    시뮬레이터 캡처 (scripts/capture_raw_screenshots.sh)
제출본 docs/screenshots/marketing/<로케일>/0N-….png   1242×2688, 이 폴더를 DeployBar 가 올린다

바탕·글자색은 제품 페이지 헤더(make_creative_assets.py)와 같다: 검정 바탕 + 앱의 키 색 청록(cue, HandsFreeMetronome/Palette.swift).
"""
import subprocess, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "screenshots" / "raw"
# 스토어 로케일 → 앱 화면 언어. 영어(영국)은 영국식 화면(en-GB)을 따로 찍고,
# 스페인어 한 벌이 es-ES · es-MX 두 페이지를 맡는다.
SCREEN = {"en-US": "en", "ko": "ko", "ja": "ja", "de-DE": "de", "es-ES": "es", "es-MX": "es",
          "fr-FR": "fr", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant", "pt-BR": "pt-BR", "it": "it", "en-GB": "en-GB",
          "ru": "ru", "nl": "nl", "pl": "pl", "tr": "tr", "sv": "sv", "da": "da", "nb": "nb", "fi": "fi", "cs": "cs", "el": "el", "th": "th", "vi": "vi", "id": "id"}
OUT = ROOT / "docs" / "screenshots" / "marketing"
WORK = pathlib.Path("/tmp") / "nmt-marketing"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 1242, 2688

# (파일, 레이아웃, 헤드라인, 서브카피) — 언어마다 따로 쓴다.
SHOTS = {
    "en-US": [
        ("01-playing.png", "hero",  "Keep both hands<br>on your instrument", "Say “start” or “faster” — no tapping"),
        ("02-orbit.png",   "left",  "See every beat<br>go around", "Orbit, bounce and ring views"),
        ("03-count.png",   "right", "Count the bar<br>at a glance", "Big numbers you can read from the stand"),
        ("04-voice.png",   "hero",  "Forgot a command?<br>Just say “help”", "Every word you can say, right on screen"),
        ("05-accents.png", "bottom","Make every<br>click your own", "Accent grid and per-song presets with Pro"),
    ],
    "ko": [
        ("01-playing.png", "hero",  "두 손은 악기에,<br>템포는 말로", "영어로 “start”, “faster” 한마디면 돼요"),
        ("02-orbit.png",   "left",  "박이 도는 게<br>눈에 보여요", "원 궤도, 튀는 공, 링 세 가지 화면"),
        ("03-count.png",   "right", "지금 몇 박인지<br>한눈에", "보면대 너머에서도 읽히는 큰 숫자"),
        ("04-voice.png",   "hero",  "명령이 생각 안 나면<br>“help”", "말할 수 있는 말을 화면에 바로 띄워 줘요"),
        ("05-accents.png", "bottom","강세를<br>마음대로", "Pro의 악센트 그리드와 곡별 프리셋"),
    ],
    "ja": [
        ("01-playing.png", "hero", "両手は楽器に、<br>テンポは声で", "英語で「start」「faster」と言うだけ"),
        ("02-orbit.png", "left", "拍がめぐるのが<br>目で見える", "オービット、バウンス、リングの3つの表示"),
        ("03-count.png", "right", "いま何拍目か<br>ひと目でわかる", "譜面台の向こうからでも読める大きな数字"),
        ("04-voice.png", "hero", "コマンドを忘れたら<br>「help」", "話せる言葉をすぐ画面に表示"),
        ("05-accents.png", "bottom", "アクセントを<br>思いのままに", "Proのアクセントグリッドと曲ごとのプリセット"),
    ],
    "de-DE": [
        ("01-playing.png", "hero", "Beide Hände<br>am Instrument", "Sag „start“ oder „faster“ – auf Englisch"),
        ("02-orbit.png", "left", "Sieh jeden Schlag<br>im Kreis laufen", "Orbit, Ball und Ring zur Auswahl"),
        ("03-count.png", "right", "Den Takt<br>auf einen Blick", "Große Zahlen, lesbar vom Notenständer"),
        ("04-voice.png", "hero", "Befehl vergessen?<br>Sag einfach „help“", "Alle Befehle direkt auf dem Bildschirm"),
        ("05-accents.png", "bottom", "Jeder Klick,<br>wie du willst", "Akzentraster und Presets pro Song mit Pro"),
    ],
    "es-ES": [
        ("01-playing.png", "hero", "Las dos manos<br>en el instrumento", "Di “start” o “faster” en inglés, sin tocar nada"),
        ("02-orbit.png", "left", "Mira cada pulso<br>dar la vuelta", "Vistas en órbita, rebote y anillo"),
        ("03-count.png", "right", "Cuenta el compás<br>de un vistazo", "Números grandes que se leen desde el atril"),
        ("04-voice.png", "hero", "¿Se te olvidó algo?<br>Di “help”", "Todo lo que puedes decir, en pantalla"),
        ("05-accents.png", "bottom", "Cada clic,<br>a tu manera", "Acentos y preajustes por canción con Pro"),
    ],
    "es-MX": [
        ("01-playing.png", "hero", "Las dos manos<br>en el instrumento", "Di “start” o “faster” en inglés, sin tocar nada"),
        ("02-orbit.png", "left", "Mira cada pulso<br>dar la vuelta", "Vistas en órbita, rebote y anillo"),
        ("03-count.png", "right", "Cuenta el compás<br>de un vistazo", "Números grandes que se leen desde el atril"),
        ("04-voice.png", "hero", "¿Se te olvidó algo?<br>Di “help”", "Todo lo que puedes decir, en pantalla"),
        ("05-accents.png", "bottom", "Cada clic,<br>a tu manera", "Acentos y preajustes por canción con Pro"),
    ],
    "fr-FR": [
        ("01-playing.png", "hero", "Les deux mains<br>sur l’instrument", "Dis « start » ou « faster », en anglais"),
        ("02-orbit.png", "left", "Vois les temps<br>tourner", "Vues orbite, rebond et anneau"),
        ("03-count.png", "right", "La mesure d’un<br>seul coup d’œil", "De grands chiffres lisibles depuis le pupitre"),
        ("04-voice.png", "hero", "Commande oubliée ?<br>Dis « help »", "Tout ce que tu peux dire, affiché à l’écran"),
        ("05-accents.png", "bottom", "Chaque clic<br>à ta façon", "Accents et préréglages par morceau, avec Pro"),
    ],
    "zh-Hans": [
        ("01-playing.png", "hero", "双手留在乐器上<br>速度开口就改", "用英文说“start”“faster”就行"),
        ("02-orbit.png", "left", "每一拍转动<br>看得见", "轨道、弹跳、环形三种视图"),
        ("03-count.png", "right", "第几拍<br>一眼看清", "隔着谱架也看得清的大数字"),
        ("04-voice.png", "hero", "忘了指令？<br>说“help”", "能说的指令直接显示在屏幕上"),
        ("05-accents.png", "bottom", "每一击的轻重<br>由你决定", "Pro 的重音网格和按曲目预设"),
    ],
    "zh-Hant": [
        ("01-playing.png", "hero", "雙手留在樂器上<br>速度開口就改", "用英文說「start」「faster」就行"),
        ("02-orbit.png", "left", "每一拍轉動<br>看得見", "軌道、彈跳、環形三種檢視"),
        ("03-count.png", "right", "第幾拍<br>一眼看清", "隔著譜架也看得清的大數字"),
        ("04-voice.png", "hero", "忘了指令？<br>說「help」", "能說的指令直接顯示在螢幕上"),
        ("05-accents.png", "bottom", "每一下的輕重<br>由你決定", "Pro 的重音格與依曲目儲存的預設"),
    ],
    "it": [
        ("01-playing.png", "hero", "Le mani<br>sullo strumento", "Dì “start” o “faster” in inglese, senza toccare"),
        ("02-orbit.png", "left", "Guarda ogni movimento<br>girare", "Viste orbita, rimbalzo e anello"),
        ("03-count.png", "right", "Conta la battuta<br>a colpo d’occhio", "Numeri grandi, leggibili dal leggio"),
        ("04-voice.png", "hero", "Comando dimenticato?<br>Dì “help”", "Tutto ciò che puoi dire, sullo schermo"),
        ("05-accents.png", "bottom", "Ogni click<br>a modo tuo", "Accenti e preset per brano con Pro"),
    ],
    "pt-BR": [
        ("01-playing.png", "hero", "As duas mãos<br>no instrumento", "Diga “start” ou “faster” — sem tocar na tela"),
        ("02-orbit.png", "left", "Veja cada tempo<br>girar na tela", "Visuais de órbita, bola e anel"),
        ("03-count.png", "right", "Conte o compasso<br>num relance", "Números grandes que dá para ler da estante"),
        ("04-voice.png", "hero", "Esqueceu o comando?<br>Diga “help”", "Tudo o que você pode dizer, direto na tela"),
        ("05-accents.png", "bottom", "Cada clique<br>do seu jeito", "Grade de acentos e presets por música no Pro"),
    ],
    "ru": [
        ("01-playing.png", "hero", "Обе руки<br>на инструменте", "Скажите «start» или «faster» — без нажатий"),
        ("02-orbit.png", "left", "Смотрите, как<br>идёт каждая доля", "Виды: орбита, мячик и кольцо"),
        ("03-count.png", "right", "Считайте такт<br>с одного взгляда", "Крупные цифры видны даже с пульта"),
        ("04-voice.png", "hero", "Забыли команду?<br>Скажите «help»", "Все команды сразу на экране"),
        ("05-accents.png", "bottom", "Каждый клик<br>по-своему", "Сетка акцентов и пресеты для пьес в Pro"),
    ],
    "nl": [
        ("01-playing.png", "hero", "Beide handen<br>op je instrument", "Zeg “start” of “faster” — geen getik"),
        ("02-orbit.png", "left", "Zie elke tel<br>rondgaan", "Baan-, stuiter- en ringweergave"),
        ("03-count.png", "right", "Tel de maat<br>in één oogopslag", "Grote cijfers, leesbaar vanaf de lessenaar"),
        ("04-voice.png", "hero", "Commando vergeten?<br>Zeg “help”", "Alles wat je kunt zeggen, op het scherm"),
        ("05-accents.png", "bottom", "Maak elke klik<br>van jezelf", "Accentenraster en presets per nummer met Pro"),
    ],
    "pl": [
        ("01-playing.png", "hero", "Obie ręce<br>na instrumencie", "Powiedz „start” lub „faster” — bez stukania"),
        ("02-orbit.png", "left", "Zobacz, jak każde<br>uderzenie krąży", "Widok odbicia, orbity i pierścienia"),
        ("03-count.png", "right", "Policz takt<br>jednym spojrzeniem", "Duże cyfry czytelne z pulpitu"),
        ("04-voice.png", "hero", "Zapomniałeś polecenia?<br>Powiedz „help”", "Wszystko, co możesz powiedzieć, na ekranie"),
        ("05-accents.png", "bottom", "Każdy klik<br>po swojemu", "Siatka akcentów i presety dla utworów w Pro"),
    ],
    "tr": [
        ("01-playing.png", "hero", "İki eliniz<br>enstrümanda", "“start” veya “faster” deyin — dokunmak yok"),
        ("02-orbit.png", "left", "Her vuruşun<br>dönüşünü görün", "Zıplama, yörünge ve halka görünümü"),
        ("03-count.png", "right", "Ölçüyü<br>tek bakışta sayın", "Nota sehpasından okunan büyük rakamlar"),
        ("04-voice.png", "hero", "Komutu mu unuttunuz?<br>“help” deyin", "Söyleyebileceğiniz her şey ekranda"),
        ("05-accents.png", "bottom", "Her tık<br>sizin elinizde", "Pro ile vurgu ızgarası ve şarkıya özel hazır ayarlar"),
    ],
    "sv": [
        ("01-playing.png", "hero", "Båda händerna<br>på instrumentet", "Säg “start” eller “faster” — inga tryck"),
        ("02-orbit.png", "left", "Se varje slag<br>gå runt", "Studs-, omlopps- och ringvy"),
        ("03-count.png", "right", "Räkna takten<br>med en blick", "Stora siffror som syns från notstället"),
        ("04-voice.png", "hero", "Glömt kommandot?<br>Säg “help”", "Allt du kan säga, direkt på skärmen"),
        ("05-accents.png", "bottom", "Gör varje klick<br>till ditt eget", "Accentrutnät och förinställningar per låt med Pro"),
    ],
    "da": [
        ("01-playing.png", "hero", "Begge hænder<br>på instrumentet", "Sig “start” eller “faster” — ingen tryk"),
        ("02-orbit.png", "left", "Se hvert slag<br>løbe rundt", "Hoppe-, kredsløbs- og ringvisning"),
        ("03-count.png", "right", "Tæl takten<br>med et blik", "Store tal, der kan læses fra nodestativet"),
        ("04-voice.png", "hero", "Glemt kommandoen?<br>Sig “help”", "Alt, du kan sige, direkte på skærmen"),
        ("05-accents.png", "bottom", "Gør hvert klik<br>til dit eget", "Accentgitter og forudindstillinger pr. sang med Pro"),
    ],
    "nb": [
        ("01-playing.png", "hero", "Begge hendene<br>på instrumentet", "Si «start» eller «faster» — ingen trykking"),
        ("02-orbit.png", "left", "Se hvert slag<br>gå rundt", "Sprett-, bane- og ringvisning"),
        ("03-count.png", "right", "Tell takten<br>med et blikk", "Store tall som kan leses fra notestativet"),
        ("04-voice.png", "hero", "Glemt kommandoen?<br>Si «help»", "Alt du kan si, rett på skjermen"),
        ("05-accents.png", "bottom", "Gjør hvert klikk<br>til ditt eget", "Aksentrutenett og forhåndsinnstillinger per sang med Pro"),
    ],
    "fi": [
        ("01-playing.png", "hero", "Molemmat kädet<br>soittimella", "Sano “start” tai “faster” — ei napautuksia"),
        ("02-orbit.png", "left", "Katso, kuinka jokainen<br>isku kiertää", "Pomppu-, rata- ja rengasnäkymä"),
        ("03-count.png", "right", "Laske tahti<br>yhdellä silmäyksellä", "Isot numerot, jotka näkyvät nuottitelineeltä"),
        ("04-voice.png", "hero", "Unohtuiko komento?<br>Sano “help”", "Kaikki sanottavat komennot näytöllä"),
        ("05-accents.png", "bottom", "Tee jokaisesta<br>naksahduksesta omasi", "Painotusruudukko ja kappalekohtaiset esiasetukset Prossa"),
    ],
    "cs": [
        ("01-playing.png", "hero", "Obě ruce<br>na nástroji", "Řekněte „start“ nebo „faster“ — žádné klepání"),
        ("02-orbit.png", "left", "Sledujte, jak každá<br>doba obíhá", "Zobrazení odrazu, dráhy a kruhu"),
        ("03-count.png", "right", "Spočítejte takt<br>jedním pohledem", "Velká čísla čitelná i z notového stojanu"),
        ("04-voice.png", "hero", "Zapomněli jste příkaz?<br>Řekněte „help“", "Vše, co lze říct, přímo na obrazovce"),
        ("05-accents.png", "bottom", "Každé klepnutí<br>po svém", "Mřížka akcentů a předvolby pro skladby v Pro"),
    ],
    "el": [
        ("01-playing.png", "hero", "Και τα δύο χέρια<br>στο όργανο", "Πείτε «start» ή «faster» — χωρίς πατήματα"),
        ("02-orbit.png", "left", "Δείτε κάθε χρόνο<br>να κάνει κύκλο", "Προβολή αναπήδησης, τροχιάς και δακτυλίου"),
        ("03-count.png", "right", "Μετρήστε το μέτρο<br>με μια ματιά", "Μεγάλοι αριθμοί ευανάγνωστοι από το αναλόγιο"),
        ("04-voice.png", "hero", "Ξεχάσατε την εντολή;<br>Πείτε «help»", "Όλες οι εντολές στην οθόνη"),
        ("05-accents.png", "bottom", "Κάθε κλικ<br>με τον δικό σας τρόπο", "Πλέγμα τόνων και προεπιλογές ανά κομμάτι με το Pro"),
    ],
    "th": [
        ("01-playing.png", "hero", "มือทั้งสองข้าง<br>อยู่กับเครื่องดนตรี", "พูดว่า “start” หรือ “faster” ไม่ต้องแตะ"),
        ("02-orbit.png", "left", "ดูทุกจังหวะ<br>หมุนไปรอบ ๆ", "มุมมองลูกบอลเด้ง วงโคจร และวงแหวน"),
        ("03-count.png", "right", "นับห้องเพลง<br>ได้ในพริบตา", "ตัวเลขใหญ่ อ่านได้จากขาตั้งโน้ต"),
        ("04-voice.png", "hero", "ลืมคำสั่งใช่ไหม<br>พูดว่า “help”", "ทุกคำที่พูดได้ แสดงบนหน้าจอ"),
        ("05-accents.png", "bottom", "ทุกเสียงคลิก<br>เป็นแบบของคุณ", "ตารางเสียงเน้นและค่าที่ตั้งไว้ต่อเพลงใน Pro"),
    ],
    "vi": [
        ("01-playing.png", "hero", "Hai tay<br>trên nhạc cụ", "Nói “start” hoặc “faster” — không cần chạm"),
        ("02-orbit.png", "left", "Nhìn từng phách<br>chạy vòng", "Chế độ nảy, quỹ đạo và vòng"),
        ("03-count.png", "right", "Đếm ô nhịp<br>trong một cái nhìn", "Số lớn, đọc được từ giá nhạc"),
        ("04-voice.png", "hero", "Quên lệnh?<br>Nói “help”", "Mọi lệnh có thể nói hiện ngay trên màn hình"),
        ("05-accents.png", "bottom", "Mỗi tiếng gõ<br>theo ý bạn", "Lưới nhấn phách và cài đặt sẵn theo bài với Pro"),
    ],
    "id": [
        ("01-playing.png", "hero", "Kedua tangan<br>di instrumen", "Ucapkan “start” atau “faster” — tanpa mengetuk"),
        ("02-orbit.png", "left", "Lihat setiap ketukan<br>berputar", "Tampilan pantul, orbit, dan cincin"),
        ("03-count.png", "right", "Hitung birama<br>sekilas pandang", "Angka besar yang terbaca dari stand not"),
        ("04-voice.png", "hero", "Lupa perintah?<br>Ucapkan “help”", "Semua yang bisa diucapkan, langsung di layar"),
        ("05-accents.png", "bottom", "Setiap klik<br>sesuai gayamu", "Kisi aksen dan preset per lagu dengan Pro"),
    ],
    "en-GB": [
        ("01-playing.png", "hero", "Keep both hands<br>on your instrument", "Say “start” or “faster” — no tapping"),
        ("02-orbit.png", "left", "See every beat<br>go around", "Orbit, bounce and ring views"),
        ("03-count.png", "right", "Count the bar<br>at a glance", "Big numbers you can read from the stand"),
        ("04-voice.png", "hero", "Forgot a command?<br>Just say “help”", "Every word you can say, right on screen"),
        ("05-accents.png", "bottom", "Make every<br>click your own", "Accent grid and per-song presets with Pro"),
    ],
}

BASE_CSS = f"""
* {{ margin:0; padding:0; box-sizing:border-box; }}
html,body {{ width:{W}px; height:{H}px; overflow:hidden; }}
body {{ background:#0a0d0f; position:relative;
  font-family:-apple-system, "SF Pro Display", "Apple SD Gothic Neo", "Hiragino Sans", "PingFang SC", sans-serif; }}
.glow {{ position:absolute; width:1200px; height:1200px; border-radius:50%; filter:blur(200px);
  background:rgba(34,211,238,.22); }}
.headline {{ font-size:104px; font-weight:800; color:#eef3f5; letter-spacing:-3px; line-height:1.14; }}
.sub {{ font-size:50px; font-weight:500; color:#9aa6ac; letter-spacing:-1px; line-height:1.3; }}
:lang(ko) .headline, :lang(ko) .sub {{ word-break:keep-all; }}
.phone {{ position:absolute; background:#17171a; border-radius:112px; border:4px solid #3a3a3e; padding:24px;
  box-shadow: 0 60px 140px rgba(0,0,0,.6); }}
.phone img {{ width:100%; display:block; border-radius:90px; }}
.t {{ position:absolute; left:90px; right:90px; }}
"""

LAYOUTS = {
    "hero": """
.glow { left:20px; top:900px; }
.t { top:230px; text-align:center; }
.sub { margin-top:44px; }
.phone { width:820px; left:211px; top:740px; }
""",
    "left": """
.glow { left:300px; top:1100px; }
.t { top:250px; text-align:left; }
.sub { margin-top:44px; }
.phone { width:820px; left:330px; top:760px; transform:rotate(-4deg); }
""",
    "right": """
.glow { left:-300px; top:1000px; }
.t { top:250px; text-align:right; }
.sub { margin-top:44px; }
.phone { width:820px; left:90px; top:760px; transform:rotate(4deg); }
""",
    "bottom": """
.glow { left:20px; top:-200px; }
.phone { width:900px; left:171px; top:-760px; }
.t { top:2030px; text-align:center; }
.sub { margin-top:44px; }
""",
}

HTML = """<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{css}</style></head>
<body><div class="glow"></div><div class="phone"><img src="{img}"></div>
<div class="t"><div class="headline">{headline}</div><div class="sub">{sub}</div></div></body></html>"""

def main(only):
    WORK.mkdir(exist_ok=True)
    for loc, shots in SHOTS.items():
        if only and loc not in only:
            continue
        (OUT / loc).mkdir(parents=True, exist_ok=True)
        for fname, layout, headline, sub in shots:
            html = WORK / f"{loc}-{fname}.html"
            html.write_text(HTML.format(lang=loc if loc in ("zh-Hans", "zh-Hant") else loc.split("-")[0], css=BASE_CSS + LAYOUTS[layout],
                                        img=(RAW / SCREEN[loc] / fname).as_uri(), headline=headline, sub=sub), encoding="utf-8")
            out = OUT / loc / fname
            # 다른 세션의 Chrome 과 겹치면 가끔 실패한다 — 새 프로필로 몇 번 다시 시도한다.
            for attempt in range(4):
                out.unlink(missing_ok=True)
                prof = WORK / f"chrome-{attempt}"
                try:
                    subprocess.run([CHROME, "--headless=new", f"--screenshot={out}", f"--window-size={W},{H}",
                                    "--force-device-scale-factor=1", "--hide-scrollbars", "--disable-gpu",
                                    "--no-first-run", f"--user-data-dir={prof}", html.as_uri()],
                                   capture_output=True, timeout=40)
                except subprocess.TimeoutExpired:
                    pass
                if out.exists() and out.stat().st_size > 0:
                    break
            else:
                sys.exit(f"렌더 실패: {out}")
            print("rendered", out.relative_to(ROOT))

if __name__ == "__main__":
    main(sys.argv[1:])
