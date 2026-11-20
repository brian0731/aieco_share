from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import Paragraph
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from xml.sax.saxutils import escape

root = Path(__file__).resolve().parents[2]
pdf = root / "output/pdf/community-lifebuoy-project-brief.pdf"
pdf.parent.mkdir(parents=True, exist_ok=True)
pdfmetrics.registerFont(TTFont("JH", r"C:\Windows\Fonts\msjh.ttc", subfontIndex=0))
pdfmetrics.registerFont(TTFont("JHB", r"C:\Windows\Fonts\msjhbd.ttc", subfontIndex=0))
w, h = A4
c = canvas.Canvas(str(pdf), pagesize=A4)
c.setTitle("社區救生圈｜專案計畫與首版驗收")
c.setAuthor("Ka-ra 光之協定")
ink, teal, light, paper, white, gray = map(HexColor,
    ("#162E30","#07685D","#E2EFEA","#F8FBF8","#FFFFFF","#446263"))
m = 51
body = w - 2 * m

def line(s, x, y, size=11, color=ink, font="JH"):
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawString(x, y, s)

def paragraph(s, x, top, width=body, size=11, leading=17, color=ink):
    p = Paragraph(escape(s), ParagraphStyle("cjk", fontName="JH",
                  fontSize=size, leading=leading, wordWrap="CJK", textColor=color))
    _, height = p.wrap(width, 650)
    p.drawOn(c, x, top - height)
    return top - height

def box(x, y, width, height, fill):
    c.setFillColor(fill)
    c.rect(x, y, width, height, fill=1, stroke=0)

def page(n, caption, title, summary):
    box(0, 0, w, h, paper)
    box(0, h-9, w, 9, teal)
    line("KA-RA  /  光之協定", m, h-52, 11, teal, "JHB")
    line(caption, m, h-96, 11, teal, "JHB")
    line(title, m, h-145, 36, ink, "JHB")
    paragraph(summary, m, h-167, body, 12, 19, gray)
    box(m, 51, body, .7, teal)
    line("社區救生圈  /  專案規格 v0.3  /  2026-11-20", m, 32, 9, gray)
    line(f"{n:02d} / 05", w-m-38, 32, 9, gray)

def entry(y, tag, title, desc):
    line(tag, m, y, 11, teal, "JHB")
    line(title, m+47, y, 15, ink, "JHB")
    end = paragraph(desc, m+47, y-11, body-47)
    box(m, end-11, body, .45, HexColor("#B9D0CB"))
    assert end > 68, (title, end)
    return end-43

def note(y, title, desc):
    p_width = body-34
    p = Paragraph(escape(desc), ParagraphStyle("note", fontName="JH",
                  fontSize=11, leading=17, wordWrap="CJK", textColor=ink))
    _, ph = p.wrap(p_width, 600)
    bottom = y-ph-55
    assert bottom > 59, (title, bottom)
    box(m, bottom, body, ph+55, light)
    line(title, m+17, y-23, 13, teal, "JHB")
    p.drawOn(c, m+17, y-37-ph)
    return bottom-27

page(1, "01  /  產品範圍", "社區救生圈",
     "在支付、物流或通訊中斷時，街坊仍能找到幫手、交換物資與維持聯絡。平日先建立信任和互助習慣，危機時才有可用的人際網絡。")
y = 598
y = entry(y, "01", "時間銀行", "街坊提出服務需求或提供技能，有人接單後約定分鐘數，服務完成由雙方各自確認。60 分鐘服務記為 1 小時，協議按整數分鐘記錄。")
y = entry(y, "02", "以物易物", "發布我有與我需要的物資，提出交換、保留及雙方確認交收。例：以手電筒交換電池，交收前即可看到物品條件與對方的確認狀態。")
y = entry(y, "03", "社區互助與聊天室", "首頁提供免費求助、資源公告及社區房間。外網可接通已核准的光網公共房間，無外網時可在同一個可互通的區域網路使用 LAN 聊天。")
y = entry(y, "04", "獨立新 App", "Flutter 從傳播光衍生，使用獨立 App ID、資料儲存與發布設定。Nuxt.js 提供管理後台與 API。首版先驗收 Android，iOS 另用 Apple 工具鏈驗證。")
note(y+12, "試點假設", "先在一個社區閉門驗收，安排社區協調人與公共交收點。把支付中斷當作設計情境。實體避難點及服務時間由社區確認後才公開。")
c.showPage()

page(2, "02  /  交易規則", "時間與物資怎麼流動",
     "把服務、交換和免費求助放在同一個入口。交易結果由後台確認，街坊可以從狀態看出下一步由誰處理。")
y = 598
y = entry(y, "A", "服務從配對到入帳", "刊登、接單、確認約定、完成服務、雙方確認、入帳。例：甲替乙修理腳踏車 30 分鐘，後台同時記甲 +30 與乙 -30。只有一方確認時，維持待確認。")
y = entry(y, "B", "帳本與重試", "MySQL 的 InnoDB 在同一交易鎖定配對和帳戶，核對社區及可用額度，再寫成對分錄。唯一結算鍵防止重複入帳。爭議暫停結算，事後更正保留原紀錄及理由。")
y = entry(y, "C", "物品保留與交收", "刊登、提案、擇一保留、安排交收、雙方確認，再完成交換。取消或逾期可釋出保留。多方同時提案只能有一筆成功保留。有爭議時由協調人接手。")
y = entry(y, "D", "免費求助與個資", "免費求助不受餘額或信用評分限制。一般貼文只露出大致區域，交收資訊限配對雙方。後台依社區區分成員與管理者權限，管理操作留下稽核紀錄。")
note(y+12, "試點前由社區決定", "確認新成員的起始額度、可用額度下限和申訴回應時限。開發以測試帳戶驗證，服務分鐘不兌現、不計利息，也不跨社區轉移。")
c.showPage()

page(3, "03  /  系統與光網", "聊天室如何互通",
     "互通從兩個相容的光網開始。管理者可逐一核對接入 App 的協議、房間與服務狀態，再擴大連線。")
y = 601
cols = (("Flutter","社區救生圈"),
        ("Nuxt / Nitro","管理後台與交易 API"),
        ("MySQL 8.4 / InnoDB","社區交易主帳"))
colw = (body-30)/3
for i, (title, text) in enumerate(cols):
    x = m+i*(colw+15)
    box(x, y-59, colw, 60, light)
    line(title, x+11, y-23, 12, teal, "JHB")
    line(text, x+11, y-44, 10)
y -= 91
y = entry(y, "01", "沿用可驗證的通訊元件", "現有傳播光支援 WebSocket relay、六位碼配對與 LAN 聊天。既有手機橋接會同步多類封包，並依賴手機保持運行。新 App 沿用相容聊天格式與 LAN 能力。")
y = entry(y, "02", "常駐橋接與接入名冊", "服務端映射已同意公開的房間，驗證 aieco.light.chat.v1，記錄來源並去重、限速及重連。管理員可暫停單一連線。六位碼查找 relay，接入與管理另行授權。")
y = entry(y, "03", "連線邊界", "橋接只轉發已核准公開房間的聊天。信用評分、帳本、交換、私訊、定位及 SOS 封包不得跨網。無外網時保留 LAN 聊天和本機草稿，復線再由 API 確認交易。")
line("核對依據", m, y+1, 11, teal, "JHB")
line("aieco_mesh @ 53a7e8a  ·  docs/CROSS_APP_CHAT.md", m, y-18, 9, gray)
line("Nuxt 官方文件  ·  nuxt.com/docs/4.x/directory-structure/server", m, y-34, 9, gray)
c.linkURL("https://nuxt.com/docs/4.x/directory-structure/server", (m, y-38, w-m, y-23))
c.showPage()

page(4, "04  /  交付與驗收", "從原型走到試點",
     "以能現場演示的結果驗收。Ka-ra 光之協定技術員負責實作與測試，社區協調人確認營運與交收規則。")
y = 607
y = entry(y, "M1", "新 App 與第一筆時間帳", "Android 新舊 App 同機安裝。以 MySQL 測試兩個帳戶結算 30 分鐘服務，驗證單方不入帳、雙方只入帳一次，並覆蓋並行確認、斷線重送和餘額不足。")
y = entry(y, "M2", "物物交換、信用評分與後台", "完成交換後雙方可互評。驗證物品不會被重複保留、取消可釋出、每人每筆交易只能評一次，以及評分公開和申訴後的重算。")
y = entry(y, "M3", "跨 App 與斷網演練", "用兩個相容 relay 雙向發訊，確認重連、去重、停用及非公開封包隔離。兩台手機在同一個 LAN 關閉外網後互傳，復線後草稿可重試但不重複結算。")
y = entry(y, "M4", "小規模試點", "交付可重跑的測試、部署說明、備份還原演練、社區聯絡窗口與新舊版本資料界線。試點追蹤互助完成數、交換完成率、爭議處理與斷網傳訊結果。")
note(y+13, "開放接入的前置條件", "取得光網 App 名冊、管理者同意與各 relay 測試設定。先驗收兩個測試 relay，再逐一驗證其餘 App。對外開通前確定首個試點社區與營運人員。")
c.showPage()

page(5, "05  /  用戶信用評分", "交易完成後互評",
     "評分反映服務與交收的履約經驗。首版採 1 至 5 星，以同社區的有效交易評價計算。")
y = 617
y = entry(y, "A", "雙方各評一次", "已入帳的時間銀行服務及已完成的物物交換，可於完成後 7 日內互評。只有交易雙方可評對方，送出後鎖定。取消、免費求助及未完成交易不開放評分。")
y = entry(y, "B", "避免跟著對方打分", "評價於雙方都送出或 7 日期限屆滿後才公開。一方未評不扣分。公開時間前，交易對方也無法查閱已送出的星數。")
y = entry(y, "C", "個人頁顯示星等與樣本", "至少有 3 位不同交易對手留下有效評價才顯示分數。每位對手只採用最近一筆有效評價再取平均，四捨五入至一位小數。3 位對手分別給 5、4、3 星時，顯示 4.0／5（3 位）。")
y = entry(y, "D", "公平使用與申訴", "資料不足顯示「評價資料不足」。同社區成員只看到匯總，不顯示評分者名單。星等不影響時間帳或免費求助，也不跨光網傳送。有爭議的交易暫不計分，管理者依處理結果恢復或排除評價並留下理由。")
note(y+13, "首版驗收", "覆蓋資格、重送、公開時點、不同對手門檻、爭議重算與跨社區隔離。舊 App 的聊天室加分不納入新 App 的交易評分。")
c.showPage()
c.save()
print(pdf)
