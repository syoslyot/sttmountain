"""
Baseline test：對現有 xlsx 執行截圖，確認 capture_sheet 本身正常。
data/raw/xlsx/ 下每個 xlsx 各跑一次 P1 截圖。
"""
import pytest
from pathlib import Path
from PIL import Image

XLSX_DIR = Path(__file__).parent.parent / "data/raw/xlsx"
ALL_XLSX = list(XLSX_DIR.rglob("*.xlsx"))


@pytest.mark.skipif(not ALL_XLSX, reason="data/raw/xlsx 無 xlsx 檔案")
@pytest.mark.parametrize("xlsx_path", ALL_XLSX, ids=lambda p: p.parent.name)
@pytest.mark.timeout(60)
def test_capture_p1(nm, xlsx_path, tmp_path):
    import openpyxl
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    p1 = nm.find_sheet(wb, nm.P1_NAMES)
    if not p1:
        pytest.skip("無 P1 sheet")
    out = tmp_path / "p1.png"
    nm.capture_sheet(xlsx_path, p1, None, out)
    assert out.exists(), "capture_sheet 未生成 PNG"
    img = Image.open(out)
    assert img.format == "PNG"
    assert img.width >= 100 and img.height >= 100, f"截圖尺寸異常：{img.width}x{img.height}"


@pytest.mark.skipif(not ALL_XLSX, reason="data/raw/xlsx 無 xlsx 檔案")
@pytest.mark.parametrize("xlsx_path", ALL_XLSX, ids=lambda p: p.parent.name)
@pytest.mark.timeout(60)
def test_capture_p2(nm, xlsx_path, tmp_path):
    import openpyxl
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    p2 = nm.find_sheet(wb, nm.P2_NAMES)
    if not p2:
        pytest.skip("無 P2 sheet")
    out = tmp_path / "p2.png"
    nm.capture_sheet(xlsx_path, p2, "B2:O12", out)
    assert out.exists(), "capture_sheet 未生成 PNG"
    img = Image.open(out)
    assert img.format == "PNG"
    assert img.width >= 100 and img.height >= 100
