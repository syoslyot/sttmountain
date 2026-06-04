import os
import sqlite3
import random
import sys
from datetime import date, timedelta
from pathlib import Path

if os.getenv("ENV") != "dev":
    print("拒絕執行：seed.py 只能在 ENV=dev 環境下執行。")
    print("請用：ENV=dev python3 scripts/seed.py")
    sys.exit(1)

DB_PATH = Path(__file__).parent.parent / "db" / "sttmount_dev.db"

REGIONS = {
    "台北": ["陽明山", "七星山", "大屯山", "觀音山", "內湖"],
    "新北": ["福隆", "瑞芳", "烏來", "三峽", "石碇"],
    "基隆": ["基隆嶼", "獅球嶺", "暖暖", "七堵"],
    "宜蘭": ["太平山", "南湖大山", "思源埡口", "翠峰湖", "蘇澳"],
    "桃園": ["拉拉山", "鎮西堡", "塔曼山", "巴陵", "復興"],
    "新竹": ["觀霧", "霞喀羅", "李棟山", "五峰"],
    "苗栗": ["雪霸", "聖稜線", "加里山", "鳥嘴山", "泰安"],
    "台中": ["梨山", "合歡山", "雪山", "馬崙山", "大雪山"],
    "花蓮": ["奇萊山", "能高山", "太魯閣", "秀姑巒山", "玉里"],
    "彰化": ["八卦山", "田中", "二水", "社頭"],
    "南投": ["玉山", "能高越嶺", "合歡山", "霧社", "奧萬大"],
    "雲林": ["草嶺", "古坑", "梅山", "林內"],
    "嘉義": ["阿里山", "玉山北峰", "塔山", "大塔山", "瑞里"],
    "台南": ["關子嶺", "曾文水庫", "玉井", "南化"],
    "高雄": ["藤枝", "六龜", "南橫", "大武山", "桃源"],
    "屏東": ["大武山", "北大武山", "霧台", "三地門", "牡丹"],
    "台東": ["新康山", "關山嶺山", "都蘭山", "知本", "海端"],
}

SUFFIXES = ["縱走隊", "登頂隊", "健行隊", "探勘隊", "溯溪隊", "攀岩隊"]

LEADER_NAMES = [
    "陳志明", "林雅惠", "黃建宏", "王怡君", "李明哲", "張雅婷",
    "劉俊賢", "吳佩珊", "蔡宗翰", "鄭淑芬", "謝志豪", "許雅雯",
    "曾建志", "蕭怡婷", "洪瑞祥", "楊淑慧", "邱志偉", "賴雅琪",
    "方建國", "葉佳穎", "潘志遠", "鍾雅玲", "江志成", "韓佩君",
    "周大偉", "余淑貞", "孫志強", "文佳慧", "石志明", "柯雅琴",
]

START = date(2018, 1, 1)
END = date(2025, 12, 31)
RANGE_DAYS = (END - START).days

LONG_RECORD = """\
第一天（2024-07-15）
0600 在登山口集合，天氣晴，溫度約25℃，隊員共8人全員到齊。
0630 正式出發，沿步道往山屋方向前進。前段坡度平緩，路況良好，偶有碎石需注意腳步。
1000 抵達第一處休息點（海拔約1800m），在此午餐補給。
1400 抵達第一山屋，紮營，晚間進行路線說明與隔日行程確認。
夜間低溫約8℃，部分隊員睡眠品質不佳，建議攜帶較厚睡袋。

第二天（2024-07-16）
0430 起床，0530 摸黑出發攻頂。氣溫約5℃，戴手套。
0830 抵達稜線，風力強勁，能見度約300公尺，霧中行進。
1000 主峰攻頂成功（海拔3886m），停留15分鐘拍照。
因霧氣過重，視野有限，決定提早下撤。
1400 回到山屋，整理裝備。
1700 完成下山，全員平安回到登山口。

備註事項：
- 此段路線部分標示模糊，建議攜帶紙本地圖。
- D2稜線段岩石濕滑，需使用冰爪或微型爪（視季節）。
- 水源：第一山屋附近有穩定水源，可補水。
- 通訊：山屋以上無手機訊號，衛星通訊或無線電必備。
- 廁所：山屋設有環保廁所，請勿野外排遺。
- 垃圾全帶下山，山屋不設廚餘桶。
隊長：陳志明
日期：2024-07-15 至 2024-07-16
"""


def ins(conn, name, date_start, date_end=None, county=None, region=None,
        region_exit=None, leader_display=None, description=None,
        extra_counties=None, gpx=None, maps=None, recs=None):
    cur = conn.execute(
        "INSERT OR IGNORE INTO expeditions"
        "(name,date_start,date_end,county,region,region_exit,leader_display,description) "
        "VALUES (?,?,?,?,?,?,?,?)",
        (name, date_start, date_end, county, region, region_exit, leader_display, description),
    )
    exp_id = cur.lastrowid
    if exp_id == 0:
        return None
    if county:
        conn.execute(
            "INSERT OR IGNORE INTO expedition_counties(expedition_id,county) VALUES (?,?)",
            (exp_id, county),
        )
    for c in (extra_counties or []):
        conn.execute(
            "INSERT OR IGNORE INTO expedition_counties(expedition_id,county) VALUES (?,?)",
            (exp_id, c),
        )
    for fname in (gpx or []):
        conn.execute(
            "INSERT OR IGNORE INTO gpx_files(expedition_id,filename,file_path) VALUES (?,?,?)",
            (exp_id, fname, fname),
        )
    for fname, ftype in (maps or []):
        conn.execute(
            "INSERT OR IGNORE INTO map_files(expedition_id,filename,file_path,file_type) VALUES (?,?,?,?)",
            (exp_id, fname, fname, ftype),
        )
    for fname, content in (recs or []):
        conn.execute(
            "INSERT OR IGNORE INTO records(expedition_id,filename,content) VALUES (?,?,?)",
            (exp_id, fname, content),
        )
    return exp_id


def seed_edge_cases(conn):
    cases = [
        # ── 日期邊界 ──────────────────────────────────────────────────────────
        dict(  # E01 超長行程（30天）
            name="玉山大縱走30日隊", date_start="2023-07-01", date_end="2023-07-30",
            county="南投", region="玉山", leader_display="陳志明",
            description="30天玉山周邊全區縱走，行程含主峰、北峰、東峰及各衛星峰。",
            gpx=["玉山大縱走30日隊_主線.gpx", "玉山大縱走30日隊_支線.gpx"],
            maps=[("玉山大縱走30日隊.pdf", "pdf")],
            recs=[("隊長日誌.txt", LONG_RECORD)],
        ),
        dict(  # E02 單日健行（date_end == date_start）
            name="陽明山單日健行隊", date_start="2024-03-15", date_end="2024-03-15",
            county="台北", region="陽明山", leader_display="林雅惠",
            description="七星山主峰單日來回，適合初學者。",
            gpx=["陽明山單日健行隊.gpx"],
        ),
        dict(  # E03 無結束日期
            name="合歡山探勘隊", date_start="2022-11-20",
            county="台中", region="合歡山", leader_display="黃建宏",
            description="合歡山冬季雪景探查，日期未定回程。",
            gpx=["合歡山探勘隊.gpx"],
            maps=[("合歡山探勘隊.pdf", "pdf")],
        ),
        dict(  # E04 跨年出隊（12/28 → 1/5）
            name="跨年霞喀羅古道縱走隊", date_start="2023-12-28", date_end="2024-01-05",
            county="新竹", region="霞喀羅", leader_display="王怡君",
            description="跨年縱走霞喀羅古道，行程橫跨兩個年度。",
            gpx=["跨年霞喀羅古道縱走隊.gpx"],
            recs=[("跨年日誌.txt", "12/31夜間在山屋舉辦跨年活動，隊員士氣高昂。")],
        ),
        dict(  # E05 古老資料（2010年）
            name="雪山早期探勘隊", date_start="2010-05-03", date_end="2010-05-07",
            county="苗栗", region="雪霸", leader_display="方建國",
            description="2010年舊資料匯入，原始記錄可能不完整。",
        ),

        # ── 欄位缺失 ──────────────────────────────────────────────────────────
        dict(  # E06 無隊長、無描述
            name="太平山健行隊", date_start="2023-08-10", date_end="2023-08-12",
            county="宜蘭", region="太平山",
        ),
        dict(  # E07 無縣市、無地區
            name="無地區資料出隊", date_start="2021-06-01", date_end="2021-06-02",
            leader_display="孫志強",
            description="資料匯入時縣市欄位遺失，系統應能正常顯示。",
        ),
        dict(  # E08 完全無附件（無GPX、無地圖、無紀錄）
            name="南橫溯溪隊", date_start="2024-09-01", date_end="2024-09-03",
            county="高雄", region="南橫", leader_display="蔡宗翰",
            description="此出隊無任何附件上傳。",
        ),

        # ── 多縣市跨境 ────────────────────────────────────────────────────────
        dict(  # E09 跨兩縣市
            name="能高越嶺古道縱走隊", date_start="2024-04-20", date_end="2024-04-24",
            county="南投", region="能高越嶺", region_exit="奇萊山",
            leader_display="鄭淑芬",
            description="由南投入山，越嶺後由花蓮出山。",
            extra_counties=["花蓮"],
            gpx=["能高越嶺古道縱走隊.gpx"],
            maps=[("能高越嶺古道縱走隊_地圖.pdf", "pdf"), ("能高越嶺古道縱走隊_高度表.pdf", "pdf")],
            recs=[("隊長紀錄.txt", "能高越嶺古道三日行，景色壯麗，天氣穩定，全員安全完成縱走。")],
        ),
        dict(  # E10 跨三縣市縱走
            name="中央山脈北一段縱走隊", date_start="2023-09-10", date_end="2023-09-18",
            county="宜蘭", region="南湖大山", region_exit="玉里",
            leader_display="謝志豪",
            description="北一段9天縱走，由宜蘭入，經花蓮，從台東出。",
            extra_counties=["花蓮", "台東"],
            gpx=["中央山脈北一段縱走隊_主線.gpx", "中央山脈北一段縱走隊_撤退路線.gpx"],
            maps=[("中央山脈北一段縱走隊.pdf", "pdf")],
            recs=[
                ("隊長日誌.txt", "北一段全段完成，途中遇強風需使用冰爪。"),
                ("隊員心得_謝.txt", "此行最大挑戰是D5的稜線路段，橫風強勁。"),
            ],
        ),
        dict(  # E11 跨四縣市（南橫全段）
            name="南橫公路全段縱走隊", date_start="2022-10-05", date_end="2022-10-14",
            county="台南", region="關子嶺", region_exit="知本",
            leader_display="許雅雯",
            description="南橫全段，由台南關子嶺出發，經高雄、嘉義山區，抵台東知本。",
            extra_counties=["高雄", "嘉義", "台東"],
            gpx=["南橫公路全段縱走隊_主線.gpx"],
            recs=[("路線報告.txt", "南橫全段行程順利，路況良好，D8遇輕微落石，繞道處理。")],
        ),

        # ── 附件極端情況 ──────────────────────────────────────────────────────
        dict(  # E12 超多GPX（5條路線）
            name="玉山五峰連登隊", date_start="2024-08-01", date_end="2024-08-07",
            county="南投", region="玉山", leader_display="曾建志",
            description="七天連登玉山主峰、北峰、東峰、南峰、前峰，每峰各一條GPX。",
            gpx=[
                "玉山五峰連登隊_主峰.gpx", "玉山五峰連登隊_北峰.gpx",
                "玉山五峰連登隊_東峰.gpx", "玉山五峰連登隊_南峰.gpx",
                "玉山五峰連登隊_前峰.gpx",
            ],
            maps=[("玉山五峰連登隊.pdf", "pdf")],
        ),
        dict(  # E13 純KML
            name="太魯閣KML測試隊", date_start="2024-05-10", date_end="2024-05-12",
            county="花蓮", region="太魯閣", leader_display="蕭怡婷",
            description="地圖資料為KML格式（非GPX），測試KML渲染。",
            gpx=["太魯閣KML測試隊.kml"],
        ),
        dict(  # E14 混合GPX+KML
            name="奇萊混合格式測試隊", date_start="2024-06-01", date_end="2024-06-03",
            county="花蓮", region="奇萊山", leader_display="洪瑞祥",
            description="同時包含GPX與KML格式，測試混合渲染。",
            gpx=["奇萊混合格式測試隊_主線.gpx", "奇萊混合格式測試隊_標記.kml"],
        ),
        dict(  # E15 超多紀錄（8人）
            name="拉拉山8人登頂隊", date_start="2023-05-20", date_end="2023-05-22",
            county="桃園", region="拉拉山", leader_display="楊淑慧",
            description="8位隊員各自撰寫出隊心得，測試多筆紀錄顯示。",
            recs=[
                ("隊長紀錄_楊.txt", "此次行程天氣絕佳，拉拉山神木群景致壯觀，全員登頂成功。"),
                ("隊員心得_王.txt", "第一次參加山社出隊，非常感謝學長姐的照顧，收穫滿滿！"),
                ("隊員心得_李.txt", "D1坡度頗陡，建議加強平時體能訓練，才能應付長距離行程。"),
                ("隊員心得_張.txt", "神木區令人震撼，樹齡超過2000年，站在旁邊深感渺小。"),
                ("隊員心得_陳.txt", "裝備方面，登山杖在下坡非常好用，強烈建議攜帶。"),
                ("隊員心得_黃.txt", "山屋環境不錯，但晚上有鼠害，食物要收好。"),
                ("隊員心得_吳.txt", "拉拉山霧氣多，能見度時好時壞，帶了備用乾糧應付延誤。"),
                ("總務報告_蔡.txt", "此次共採購食材8000元，人均約1000元，建議下次統一採購登山食品。"),
            ],
        ),
        dict(  # E16 只有地圖無GPX
            name="北大武山地圖測試隊", date_start="2024-02-14", date_end="2024-02-17",
            county="屏東", region="北大武山", leader_display="邱志偉",
            description="僅有地圖PDF，無GPX軌跡，測試無地圖時的顯示狀況。",
            maps=[
                ("北大武山地圖測試隊_地形圖.pdf", "pdf"),
                ("北大武山地圖測試隊_路線圖.pdf", "pdf"),
                ("北大武山地圖測試隊_山屋位置.pdf", "pdf"),
            ],
            recs=[("隊長紀錄.txt", "北大武山天氣變化快速，此次行程D2遇暴雨，提前撤退。")],
        ),
        dict(  # E17 只有紀錄、無GPX無地圖
            name="古坑探查隊", date_start="2021-03-05", date_end="2021-03-06",
            county="雲林", region="古坑", leader_display="賴雅琪",
            description="老資料補錄，當時無GPS設備，僅有文字紀錄。",
            recs=[
                ("紀錄一.txt", "古坑一日健行，步道整修中，部分路段需繞行，全程約5小時。"),
                ("紀錄二.txt", "午餐在山頂涼亭享用，雲海景觀極佳，天氣晴朗無雲。"),
            ],
        ),

        # ── 顯示壓力測試 ──────────────────────────────────────────────────────
        dict(  # E18 超長出隊名稱
            name="成功大學登山社一○七學年度第二學期期末大型多日縱走聯合出隊",
            date_start="2019-06-15", date_end="2019-06-22",
            county="南投", region="合歡山", leader_display="潘志遠",
            description="學年度聯合出隊，全社共42人參加。",
            gpx=["成功大學登山社聯合出隊.gpx"],
        ),
        dict(  # E19 超長描述
            name="大雪山深度探勘隊", date_start="2023-10-01", date_end="2023-10-05",
            county="台中", region="大雪山", leader_display="鍾雅玲",
            description=(
                "大雪山林道全段探勘計畫，目標建立完整的林道資料庫。"
                "此次行程共計5天，預計走完大雪山國家森林遊樂區全區主要步道，"
                "包含大雪山主峰、小雪山、橫嶺山及周邊衛星峰。"
                "隊伍共12人，含4位嚮導、6位隊員及2位紀錄人員。"
                "全程預計拍攝超過500張照片及15段影片，做為後續路線報告使用。"
                "出發前已取得林務局入山許可及國家公園入園申請，相關文件隨身攜帶。"
                "緊急聯絡人為山協指導老師，衛星電話已測試正常。"
                "裝備清單、行前訓練記錄及醫療準備均已完成，預計順利完成所有行程目標。"
            ),
            gpx=["大雪山深度探勘隊.gpx"],
            maps=[("大雪山深度探勘隊.pdf", "pdf")],
        ),

        # ── 分頁壓力測試（同地區大量出隊，測試 region list 與 pagination）──────
        *[dict(
            name=f"阿里山健行隊第{i+1:02d}期",
            date_start=(date(2020, 1, 1) + timedelta(days=i * 20)).strftime("%Y-%m-%d"),
            date_end=(date(2020, 1, 1) + timedelta(days=i * 20 + 2)).strftime("%Y-%m-%d"),
            county="嘉義", region="阿里山",
            leader_display=random.choice(LEADER_NAMES),
            description=f"阿里山第{i+1}期例行健行，天氣良好。",
            gpx=[f"阿里山健行隊第{i+1:02d}期.gpx"] if i % 2 == 0 else None,
        ) for i in range(25)],  # 25筆同地區 → 超過 PAGE=20，觸發分頁
    ]
    inserted = 0
    for kwargs in cases:
        if ins(conn, **kwargs) is not None:
            inserted += 1
    print(f"  邊界案例：插入 {inserted} 筆")
    return inserted


def seed_random(conn, n=100):
    inserted = skipped = 0
    start = date(2015, 1, 1)
    end = date(2025, 12, 31)
    days = (end - start).days

    for _ in range(n):
        county = random.choice(list(REGIONS.keys()))
        region = random.choice(REGIONS[county])
        suffix = random.choice(SUFFIXES)
        name = f"{region}{suffix}"
        d_start = start + timedelta(days=random.randint(0, days))
        d_end = None
        if random.random() < 0.7:
            d_end = d_start + timedelta(days=random.randint(1, 10))
        date_start = d_start.strftime("%Y-%m-%d")
        date_end = d_end.strftime("%Y-%m-%d") if d_end else None
        leader_display = random.choice(LEADER_NAMES) if random.random() < 0.85 else None
        description = f"{county}{region}登山活動，行程{(d_end - d_start).days}天。" if d_end else None

        gpx, maps, recs = [], [], []

        r_gpx = random.random()
        if r_gpx < 0.6:
            n_gpx = random.choices([1, 2, 3], weights=[6, 3, 1])[0]
            labels = [None, "支線A", "支線B"][:n_gpx]
            for label in labels:
                ext = random.choices([".gpx", ".kml"], weights=[9, 1])[0]
                suffix_str = f"_{label}" if label else ""
                gpx.append(f"{name}{suffix_str}{ext}")

        if random.random() < 0.5:
            n_map = random.choices([1, 2, 3], weights=[6, 3, 1])[0]
            map_labels = [("地圖", "pdf"), ("高度表", "pdf"), ("衛星圖", "pdf")][:n_map]
            for label, ftype in map_labels:
                suffix_str = f"_{label}" if n_map > 1 else ""
                maps.append((f"{name}{suffix_str}.pdf", ftype))

        if random.random() < 0.6:
            n_rec = random.choices([1, 2, 3], weights=[5, 3, 2])[0]
            rec_labels = ["隊長紀錄", "隊員心得A", "隊員心得B"][:n_rec]
            for label in rec_labels:
                recs.append((
                    f"{region}_{label}.txt",
                    f"【{label}】{name} 出隊紀錄。日期：{date_start}。地點：{county} · {region}。",
                ))

        exp_id = ins(conn, name=name, date_start=date_start, date_end=date_end,
                     county=county, region=region, leader_display=leader_display, description=description,
                     gpx=gpx or None, maps=maps or None, recs=recs or None)
        if exp_id:
            inserted += 1
        else:
            skipped += 1

    print(f"  隨機資料：插入 {inserted} 筆，跳過 {skipped} 筆（UNIQUE 衝突）")
    return inserted


def seed(append: bool = False):
    if not DB_PATH.exists():
        print(f"DB 不存在：{DB_PATH}，請先執行 init_db()")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")

    if not append:
        for tbl in ("records", "map_files", "gpx_files", "expedition_counties", "expeditions"):
            conn.execute(f"DELETE FROM {tbl}")
        conn.commit()
        print("已清空所有資料。")

    seed_edge_cases(conn)
    conn.commit()
    seed_random(conn)
    conn.commit()
    conn.close()


if __name__ == "__main__":
    seed(append="--append" in sys.argv)
