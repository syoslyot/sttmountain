import os
import sys
import pytest
from pathlib import Path
from unittest.mock import MagicMock, patch

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"

# normalize.py 第 34-36 行在 import 時就讀 env var 並建立 Supabase client，
# 必須在 import 發生前設好假值，否則 KeyError。
os.environ.setdefault("SUPABASE_URL", "http://mock.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_KEY", "mock_key")


@pytest.fixture(scope="session", autouse=True)
def mock_supabase():
    mock_client = MagicMock()
    with patch("supabase.create_client", return_value=mock_client):
        sys.modules.pop("normalize", None)
        sys.path.insert(0, str(SCRIPTS_DIR))
        import normalize
        normalize.supabase = mock_client
        yield mock_client


@pytest.fixture(scope="session")
def nm(mock_supabase):
    import normalize
    return normalize
