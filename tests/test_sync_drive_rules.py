import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest


@pytest.fixture(scope="module")
def sd():
    sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
    import sync_drive
    return sync_drive


def folder(sd, id_, name):
    return {"id": id_, "name": name, "mimeType": sd.FOLDER_MIME, "createdTime": "2026-06-01T00:00:00Z"}


def file(sd, id_, name, mime="application/octet-stream"):
    return {"id": id_, "name": name, "mimeType": mime, "modifiedTime": "2026-06-01T00:00:00Z"}


def patch_tree(monkeypatch, sd, tree):
    monkeypatch.setattr(sd, "list_folder", lambda _service, folder_id: tree.get(folder_id, []))


def test_team_folder_name_accepts_loose_new_format(sd):
    assert sd.is_team_folder_name("[2D活]舊古樓嘍嘍_20260418")
    assert sd.is_team_folder_name("［2D活］舊古樓嘍嘍20260418")
    assert sd.extract_team_title("[2D活]舊古樓嘍嘍_20260418") == "舊古樓嘍嘍"
    assert sd.extract_team_title("［2D活］舊古樓嘍嘍20260418") == "舊古樓嘍嘍"


def test_team_folder_name_rejects_non_team_folders(sd):
    assert not sd.is_team_folder_name("活動總表")
    assert not sd.is_team_folder_name("[活]舊古樓嘍嘍_20260418")
    assert not sd.is_team_folder_name("[2活]舊古樓嘍嘍_20260418")


def test_classify_top_folder_requires_team_name_and_zhijian(monkeypatch, sd):
    top = folder(sd, "top", "[2D活]舊古樓嘍嘍_20260418")
    tree = {
        "top": [
            file(sd, "xlsx", "舊古樓嘍嘍計畫書.xlsx"),
            folder(sd, "submission", "上繳航跡與紀錄"),
        ],
    }
    patch_tree(monkeypatch, sd, tree)

    kind, _items, zhijian, teams = sd.classify_top_folder(None, top)

    assert kind == "solo"
    assert zhijian["id"] == "xlsx"
    assert teams == []


def test_classify_top_folder_skips_invalid_folder_even_with_zhijian(monkeypatch, sd):
    top = folder(sd, "top", "活動總表")
    tree = {"top": [file(sd, "xlsx", "活動總表直企.xlsx")]}
    patch_tree(monkeypatch, sd, tree)

    kind, _items, zhijian, teams = sd.classify_top_folder(None, top)

    assert kind == "skip"
    assert zhijian is None
    assert teams == []


def test_classify_group_uses_only_valid_team_children_with_zhijian(monkeypatch, sd):
    top = folder(sd, "top", "大眾化活動")
    valid_team = folder(sd, "team-a", "［3C］眠月線20260601")
    no_zhijian = folder(sd, "team-b", "[2D]沒有直企_20260602")
    invalid_team = folder(sd, "team-c", "工作資料")
    tree = {
        "top": [valid_team, no_zhijian, invalid_team],
        "team-a": [file(sd, "numbers", "眠月線.numbers")],
        "team-b": [file(sd, "readme", "說明.txt")],
        "team-c": [file(sd, "xlsx", "工作資料直企.xlsx")],
    }
    patch_tree(monkeypatch, sd, tree)

    kind, _items, zhijian, teams = sd.classify_top_folder(None, top)

    assert kind == "group"
    assert zhijian is None
    assert [team[0]["id"] for team in teams] == ["team-a"]


def test_sync_expedition_files_recurses_and_classifies_supported_files(monkeypatch, sd, tmp_path):
    submission = folder(sd, "submission", "上繳航跡與紀錄")
    maps = folder(sd, "maps", "地圖")
    ignored = folder(sd, "ignored", "其他資料")
    tree = {
        "submission": [
            folder(sd, "tracks", "航跡"),
            folder(sd, "records", "紀錄"),
            file(sd, "ignored-sheet", "統計.xlsx"),
        ],
        "tracks": [
            file(sd, "gpx", "route.gpx"),
            file(sd, "kml", "route.kml"),
        ],
        "records": [
            file(sd, "pdf", "record.pdf"),
            file(sd, "doc", "record-doc", sd.GDOC_MIME),
        ],
        "maps": [
            file(sd, "map", "map.pdf"),
            folder(sd, "nested-map", "掃描"),
            file(sd, "wrong-track", "map-folder-track.gpx"),
        ],
        "nested-map": [file(sd, "jpg", "map.jpg")],
        "ignored": [file(sd, "ignored-gpx", "ignored.gpx")],
    }
    patch_tree(monkeypatch, sd, tree)

    monkeypatch.setattr(sd, "GPX_DIR", tmp_path / "gpx")
    monkeypatch.setattr(sd, "MAPS_DIR", tmp_path / "maps")
    monkeypatch.setattr(sd, "TXT_DIR", tmp_path / "txt")
    monkeypatch.setattr(sd, "download_file", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(sd, "download_google_doc", lambda *_args, **_kwargs: None)

    result = sd.sync_expedition_files(
        None,
        [submission, maps, ignored],
        "[2D]測試隊_20260601",
        datetime.fromtimestamp(0, tz=timezone.utc),
        True,
        [],
    )

    assert [f["name"] for f in result["gpx_files"]] == ["route.gpx", "route.kml"]
    assert [f["name"] for f in result["map_files"]] == ["map.pdf", "map.jpg"]
    assert [f["name"] for f in result["record_files"]] == ["record.pdf", "record-doc.txt"]
