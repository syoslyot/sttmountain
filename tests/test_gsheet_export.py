"""
Integration test：Google Sheet → xlsx → capture_sheet。

需要設定環境變數才會執行：
  GDRIVE_CREDENTIALS_JSON  — service account JSON 字串
  GDRIVE_TEST_SHEET_ID     — 要測試的 Google Sheet file ID

前置作業：
  在 Google Drive 建立一個含「直企P1(列印)」和「直企P2(列印)」sheet 的試算表，
  分享給 service account（Viewer 權限即可），記下 file ID。

執行方式：
  GDRIVE_CREDENTIALS_JSON='...' GDRIVE_TEST_SHEET_ID='abc123' \
    python3 -m pytest tests/test_gsheet_export.py -v --timeout=120
"""
import json
import os
import sys
import pytest
from pathlib import Path
from PIL import Image

HAS_CREDS    = bool(os.environ.get("GDRIVE_CREDENTIALS_JSON"))
HAS_SHEET_ID = bool(os.environ.get("GDRIVE_TEST_SHEET_ID"))
SKIP_REASON  = "需要 GDRIVE_CREDENTIALS_JSON 和 GDRIVE_TEST_SHEET_ID 環境變數"


@pytest.fixture(scope="module")
def real_service():
    from google.oauth2.service_account import Credentials
    from googleapiclient.discovery import build
    creds = Credentials.from_service_account_info(
        json.loads(os.environ["GDRIVE_CREDENTIALS_JSON"]),
        scopes=["https://www.googleapis.com/auth/drive.readonly"],
    )
    return build("drive", "v3", credentials=creds)


@pytest.fixture(scope="module")
def sd():
    sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
    import sync_drive
    return sync_drive


@pytest.mark.skipif(not (HAS_CREDS and HAS_SHEET_ID), reason=SKIP_REASON)
@pytest.mark.timeout(60)
def test_gsheet_produces_xlsx(sd, real_service, tmp_path):
    dest = tmp_path / "exported.xlsx"
    result = sd.download_google_sheet_as_xlsx(
        real_service, os.environ["GDRIVE_TEST_SHEET_ID"], dest
    )
    assert result is not None, "download_google_sheet_as_xlsx 回傳 None"
    assert result.exists(), "匯出的 xlsx 不存在"
    assert result.suffix.lower() == ".xlsx"


@pytest.mark.skipif(not (HAS_CREDS and HAS_SHEET_ID), reason=SKIP_REASON)
@pytest.mark.timeout(60)
def test_gsheet_xlsx_has_p1_sheet(sd, nm, real_service, tmp_path):
    dest = tmp_path / "exported.xlsx"
    result = sd.download_google_sheet_as_xlsx(
        real_service, os.environ["GDRIVE_TEST_SHEET_ID"], dest
    )
    import openpyxl
    wb = openpyxl.load_workbook(result, data_only=True)
    p1 = nm.find_sheet(wb, nm.P1_NAMES)
    assert p1 is not None, f"匯出的 xlsx 找不到 P1 sheet，實際 sheets：{wb.sheetnames}"


@pytest.mark.skipif(not (HAS_CREDS and HAS_SHEET_ID), reason=SKIP_REASON)
@pytest.mark.timeout(120)
def test_gsheet_capture_p1(sd, nm, real_service, tmp_path):
    """端對端：gsheet → xlsx → capture_sheet → PNG"""
    import openpyxl
    dest = tmp_path / "exported.xlsx"
    result = sd.download_google_sheet_as_xlsx(
        real_service, os.environ["GDRIVE_TEST_SHEET_ID"], dest
    )
    wb = openpyxl.load_workbook(result, data_only=True)
    p1 = nm.find_sheet(wb, nm.P1_NAMES)
    assert p1 is not None, f"匯出的 xlsx 找不到 P1 sheet，實際 sheets：{wb.sheetnames}"
    out = tmp_path / "p1.png"
    nm.capture_sheet(result, p1, None, out)
    assert out.exists(), "截圖未生成"
    img = Image.open(out)
    assert img.format == "PNG"
    assert img.width >= 100 and img.height >= 100, f"截圖尺寸異常：{img.width}x{img.height}"
