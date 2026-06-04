"""
Integration tests for expedition edit RPCs (migration 0030 + 0031).

Tests:
  - sync_expedition_members  : 只有 approved leader / staff 可呼叫
  - save_expedition_journal  : approved leader / staff / can_edit 成員 可呼叫
  - get_expedition_members   : 回傳正確成員與 profile 資料

Test accounts (建立 by integration/conftest.py):
  leader  = test_cheng@stt.test   (staff profile, expedition leader)
  staff   = test_yeh@stt.test     (staff profile, not leader)
  can_ed  = test_lin@stt.test     (member, can_edit=true)
  no_ed   = test_chen@stt.test    (member, can_edit=false)
  outside = test_huang@stt.test   (member, not in expedition)

Password: test1234
"""

import os
import uuid
import pytest
from supabase import create_client

from tests.integration.conftest import auth_client_for, URL, ANON_KEY, SVC_KEY

PASSWORD = "test1234"


# ── helpers ───────────────────────────────────────────────────────────────────

def svc_client():
    return create_client(URL, SVC_KEY)

def rpc_ok(client, fn: str, params: dict):
    r = client.rpc(fn, params).execute()
    assert r.data is not None or r.data == [], f"{fn} unexpectedly failed"

def rpc_err(client, fn: str, params: dict):
    try:
        client.rpc(fn, params).execute()
        assert False, f"{fn} should have raised but returned successfully"
    except Exception as e:
        err = str(e).lower()
        assert "unauthorized" in err or "error" in err, f"Unexpected error: {e}"


# ── expedition fixture ────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def expedition(users):
    """
    建立測試隊伍並設置成員，yield expedition_id，結束後清除。
    depends on `users` fixture (session scope) for UUIDs.
    """
    admin = svc_client()

    groups = admin.from_("expedition_groups").select("id").limit(1).execute()
    assert groups.data, "No expedition_groups found"
    group_id = groups.data[0]["id"]

    tag = str(uuid.uuid4())[:8]
    exp = admin.from_("expeditions").insert({
        "group_id":        group_id,
        "drive_folder_id": f"TEST_{tag}",
        "name":            f"[TEST] 測試隊伍 {tag}",
        "date_start":      "2099-01-01",
        "is_public":       False,
    }).execute()
    eid = exp.data[0]["id"]

    admin.from_("expedition_members").insert([
        {"expedition_id": eid, "user_id": users["leader"],
         "role": "leader", "status": "approved", "can_edit": True},
        {"expedition_id": eid, "user_id": users["can_ed"],
         "role": "member", "status": "approved",
         "expedition_role": "隊員", "can_edit": True},
        {"expedition_id": eid, "user_id": users["no_ed"],
         "role": "member", "status": "approved",
         "expedition_role": "嚮導", "can_edit": False},
    ]).execute()

    yield {"eid": eid, "uids": users}

    admin.from_("expedition_members").delete().eq("expedition_id", eid).execute()
    admin.from_("expeditions").delete().eq("id", eid).execute()


# ── sync_expedition_members ───────────────────────────────────────────────────

class TestSyncExpeditionMembers:
    def _members(self, users):
        return [
            {"user_id": users["can_ed"],  "expedition_role": "隊員", "can_edit": True},
            {"user_id": users["no_ed"],   "expedition_role": "嚮導", "can_edit": False},
        ]

    def test_leader_can_sync(self, expedition):
        eid, uids = expedition["eid"], expedition["uids"]
        rpc_ok(auth_client_for("leader"), "sync_expedition_members",
               {"p_expedition_id": eid, "p_members": self._members(uids)})

    def test_staff_can_sync(self, expedition):
        eid, uids = expedition["eid"], expedition["uids"]
        rpc_ok(auth_client_for("staff"), "sync_expedition_members",
               {"p_expedition_id": eid, "p_members": self._members(uids)})

    def test_member_cannot_sync(self, expedition):
        eid, uids = expedition["eid"], expedition["uids"]
        rpc_err(auth_client_for("can_ed"), "sync_expedition_members",
                {"p_expedition_id": eid, "p_members": self._members(uids)})

    def test_outside_user_cannot_sync(self, expedition):
        eid, uids = expedition["eid"], expedition["uids"]
        rpc_err(auth_client_for("outside"), "sync_expedition_members",
                {"p_expedition_id": eid, "p_members": self._members(uids)})

    def test_sync_replaces_members(self, expedition):
        """sync 後 DB 裡的 non-leader 成員應只剩送入的名單。"""
        eid, uids = expedition["eid"], expedition["uids"]
        only_one = [{"user_id": uids["can_ed"], "expedition_role": "隊員", "can_edit": True}]
        auth_client_for("leader").rpc("sync_expedition_members",
            {"p_expedition_id": eid, "p_members": only_one}).execute()

        rows = svc_client() \
            .from_("expedition_members") \
            .select("user_id") \
            .eq("expedition_id", eid) \
            .eq("role", "member") \
            .execute()
        assert [r["user_id"] for r in rows.data] == [uids["can_ed"]]

        # 還原
        auth_client_for("leader").rpc("sync_expedition_members",
            {"p_expedition_id": eid, "p_members": self._members(uids)}).execute()


# ── save_expedition_journal ───────────────────────────────────────────────────

SAMPLE_BLOCKS = [
    {"type": "text", "text": "<p>測試段落</p>"},
    {"type": "image", "cap": "測試圖說"},
]

class TestSaveExpeditionJournal:
    def _params(self, eid):
        return {"p_expedition_id": eid, "p_blocks": SAMPLE_BLOCKS}

    def test_leader_can_save(self, expedition):
        rpc_ok(auth_client_for("leader"), "save_expedition_journal",
               self._params(expedition["eid"]))

    def test_staff_can_save(self, expedition):
        rpc_ok(auth_client_for("staff"), "save_expedition_journal",
               self._params(expedition["eid"]))

    def test_can_edit_member_can_save(self, expedition):
        rpc_ok(auth_client_for("can_ed"), "save_expedition_journal",
               self._params(expedition["eid"]))

    def test_no_edit_member_cannot_save(self, expedition):
        rpc_err(auth_client_for("no_ed"), "save_expedition_journal",
                self._params(expedition["eid"]))

    def test_outside_user_cannot_save(self, expedition):
        rpc_err(auth_client_for("outside"), "save_expedition_journal",
                self._params(expedition["eid"]))

    def test_blocks_persisted_correctly(self, expedition):
        """儲存後 DB 裡的 journal_blocks 應與送入的一致。"""
        auth_client_for("leader").rpc("save_expedition_journal",
            self._params(expedition["eid"])).execute()

        row = svc_client() \
            .from_("expeditions") \
            .select("journal_blocks") \
            .eq("id", expedition["eid"]) \
            .single() \
            .execute()
        assert row.data["journal_blocks"] == SAMPLE_BLOCKS


# ── get_expedition_members ────────────────────────────────────────────────────

class TestGetExpeditionMembers:
    def _get(self, expedition):
        c = auth_client_for("leader")
        r = c.rpc("get_expedition_members",
                  {"p_expedition_id": expedition["eid"]}).execute()
        return {row["user_id"]: row for row in r.data}

    def test_returns_approved_members(self, expedition):
        uids = expedition["uids"]
        by_uid = self._get(expedition)
        assert uids["leader"]  in by_uid
        assert uids["can_ed"]  in by_uid
        assert uids["no_ed"]   in by_uid
        assert uids["outside"] not in by_uid

    def test_joins_profile_name(self, expedition):
        uids = expedition["uids"]
        by_uid = self._get(expedition)
        assert by_uid[uids["leader"]]["name"] == "程效賢"
        assert by_uid[uids["can_ed"]]["name"] == "林宥辰"

    def test_can_edit_flag_correct(self, expedition):
        uids = expedition["uids"]
        by_uid = self._get(expedition)
        assert by_uid[uids["can_ed"]]["can_edit"] is True
        assert by_uid[uids["no_ed"]]["can_edit"]  is False

    def test_expedition_role_correct(self, expedition):
        uids = expedition["uids"]
        by_uid = self._get(expedition)
        assert by_uid[uids["no_ed"]]["expedition_role"] == "嚮導"

    def test_pending_member_excluded(self, expedition):
        """status=pending 的成員不應出現在結果裡。"""
        eid, uids = expedition["eid"], expedition["uids"]
        admin = svc_client()
        admin.from_("expedition_members").insert({
            "expedition_id": eid,
            "user_id":       uids["outside"],
            "role":          "member",
            "status":        "pending",
            "can_edit":      False,
        }).execute()

        by_uid = self._get(expedition)
        assert uids["outside"] not in by_uid

        admin.from_("expedition_members") \
            .delete() \
            .eq("expedition_id", eid) \
            .eq("user_id", uids["outside"]) \
            .execute()
