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
    "新竹": ["觀霧", "霞喀羅", "鎮西堡", "李棟山", "五峰"],
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


def rand_date():
    return START + timedelta(days=random.randint(0, RANGE_DAYS))


def seed(append: bool = False):
    if not DB_PATH.exists():
        print(f"DB 不存在：{DB_PATH}，請先執行 init_db()")
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")

    if not append:
        for tbl in ("records", "map_files", "gpx_files", "expeditions"):
            conn.execute(f"DELETE FROM {tbl}")
        conn.commit()
        print("已清空所有資料。")

    inserted = 0
    skipped = 0

    for _ in range(200):
        county = random.choice(list(REGIONS.keys()))
        region = random.choice(REGIONS[county])
        suffix = random.choice(SUFFIXES)
        name = f"{region}{suffix}"
        d_start = rand_date()
        d_end = None
        if random.random() < 0.5:
            d_end = d_start + timedelta(days=random.randint(1, 5))
        date_start = d_start.strftime("%Y-%m-%d")
        date_end = d_end.strftime("%Y-%m-%d") if d_end else None
        description = f"{county}{region}一帶的登山活動，行程約{(d_end - d_start).days if d_end else 1}天。" if d_end else None

        leader = random.choice(LEADER_NAMES)
        cur = conn.execute(
            "INSERT OR IGNORE INTO expeditions(name, date_start, date_end, county, region, leader, description) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (name, date_start, date_end, county, region, leader, description),
        )
        conn.commit()

        if cur.lastrowid == 0:
            skipped += 1
            continue

        exp_id = cur.lastrowid
        inserted += 1

        # gpx_files: 50% 機率有，有則 1–3 筆
        if random.random() < 0.5:
            n_gpx = random.randint(1, 3)
            labels = ["主線", "支線A", "支線B"][:n_gpx]
            for label in labels:
                suffix = f"_{label}" if n_gpx > 1 else ""
                fname = f"{name}{suffix}.gpx"
                conn.execute(
                    "INSERT OR IGNORE INTO gpx_files(expedition_id, filename, file_path) VALUES (?, ?, ?)",
                    (exp_id, fname, fname),
                )

        # map_files: 50% 機率有，有則 1–2 筆
        if random.random() < 0.5:
            n_map = random.randint(1, 2)
            map_labels = [("地圖", "pdf"), ("高度表", "pdf")][:n_map]
            for label, ftype in map_labels:
                suffix = f"_{label}" if n_map > 1 else ""
                fname = f"{name}{suffix}.pdf"
                conn.execute(
                    "INSERT OR IGNORE INTO map_files(expedition_id, filename, file_path, file_type) VALUES (?, ?, ?, ?)",
                    (exp_id, fname, fname, ftype),
                )

        # records: 50% 機率有，有則 1–3 筆
        if random.random() < 0.5:
            n_rec = random.randint(1, 3)
            rec_labels = ["隊長紀錄", "隊員紀錄A", "隊員紀錄B"][:n_rec]
            for label in rec_labels:
                fname = f"{region}_{label}.txt"
                conn.execute(
                    "INSERT OR IGNORE INTO records(expedition_id, filename, content) VALUES (?, ?, ?)",
                    (exp_id, fname, f"【{label}】{name} 出隊紀錄。日期：{date_start}。地點：{county} · {region}。"),
                )

    conn.commit()
    conn.close()

    print(f"已插入 {inserted} 筆 expeditions，跳過 {skipped} 筆（UNIQUE 衝突）。")


if __name__ == "__main__":
    seed(append="--append" in sys.argv)
