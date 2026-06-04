"""
Integration test conftest.
1. 覆蓋 parent conftest 的 mock env
2. 用 GoTrue admin REST API 建立測試帳號（UUID 由 Supabase 自動產生）
3. 提供 `users` session fixture 供各 test 使用
"""
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(
    Path(__file__).parent.parent.parent.parent / "sttmountaincrazy" / ".env.local",
    override=True,
)

import os
import httpx
import pytest
from supabase import create_client

URL      = os.environ["SUPABASE_URL"]
ANON_KEY = os.environ["SUPABASE_ANON_KEY"]
SVC_KEY  = os.environ["SUPABASE_SERVICE_KEY"]
PASSWORD = "test1234"

AUTH_HEADERS = {
    "Authorization": f"Bearer {SVC_KEY}",
    "apikey":        SVC_KEY,
    "Content-Type":  "application/json",
}

# 5 個角色定義（UUID 由 Supabase 產生後回填）
USER_DEFS = [
    {"key": "leader",  "email": "test_cheng@stt.test", "name": "程效賢", "nickname": "Echo",  "profile_role": "staff"},
    {"key": "staff",   "email": "test_yeh@stt.test",   "name": "葉桐",   "nickname": "Maple", "profile_role": "staff"},
    {"key": "can_ed",  "email": "test_lin@stt.test",   "name": "林宥辰", "nickname": "Roy",   "profile_role": "member"},
    {"key": "no_ed",   "email": "test_chen@stt.test",  "name": "陳雅婷", "nickname": "Tina",  "profile_role": "member"},
    {"key": "outside", "email": "test_huang@stt.test", "name": "黃柏翰", "nickname": "Bo",    "profile_role": "member"},
]


def _list_auth_users() -> list[dict]:
    r = httpx.get(f"{URL}/auth/v1/admin/users?per_page=200", headers=AUTH_HEADERS)
    r.raise_for_status()
    return r.json().get("users", [])


def _create_auth_user(email: str) -> str:
    """建立帳號並回傳 uuid。"""
    r = httpx.post(f"{URL}/auth/v1/admin/users", headers=AUTH_HEADERS, json={
        "email":         email,
        "password":      PASSWORD,
        "email_confirm": True,
    })
    r.raise_for_status()
    return r.json()["id"]


def _delete_auth_user(uid: str):
    httpx.delete(f"{URL}/auth/v1/admin/users/{uid}", headers=AUTH_HEADERS)


@pytest.fixture(scope="session", autouse=True)
def mock_supabase():
    """覆蓋 parent conftest 的全域 mock — integration tests 打真實 Supabase。"""
    yield


@pytest.fixture(scope="session")
def users() -> dict[str, str]:
    """
    建立（或取得）5 個測試帳號，回傳 {role_key: uuid} mapping。
    Session scope — 整個測試跑一次。
    """
    admin = create_client(URL, SVC_KEY)

    # 先取得現有 auth 帳號的 email→id 對照
    existing = {u["email"]: u["id"] for u in _list_auth_users()}

    uid_map: dict[str, str] = {}
    for d in USER_DEFS:
        if d["email"] in existing:
            uid = existing[d["email"]]
        else:
            uid = _create_auth_user(d["email"])

        # 建立/更新 user_profiles
        admin.from_("user_profiles").upsert({
            "user_id":  uid,
            "name":     d["name"],
            "nickname": d["nickname"],
            "role":     d["profile_role"],
        }, on_conflict="user_id").execute()

        uid_map[d["key"]] = uid

    yield uid_map
    # 測試完成後保留帳號，下次重用


def auth_client_for(role_key: str):
    """以某角色登入並回傳已正確設定 auth header 的 Supabase client。"""
    from supabase import create_client as _cc
    email = next(d["email"] for d in USER_DEFS if d["key"] == role_key)
    c = _cc(URL, ANON_KEY)
    r = c.auth.sign_in_with_password({"email": email, "password": PASSWORD})
    assert r.user is not None, f"Login failed for {role_key} ({email})"
    # 明確把 access_token 設給 PostgREST client，否則它仍用 anon key
    c.postgrest.auth(r.session.access_token)
    return c
