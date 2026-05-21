import os
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()
load_dotenv(".env.local", override=True)

SUPABASE_URL  = os.environ.get("SUPABASE_URL", "")
SUPABASE_ANON = os.environ.get("SUPABASE_ANON_KEY", "")
STORAGE_BASE  = f"{SUPABASE_URL}/storage/v1/object/public"

_client: Client | None = None


def _get_client() -> Client:
    global _client
    if _client is None:
        _client = create_client(
            os.environ["SUPABASE_URL"],
            os.environ["SUPABASE_ANON_KEY"],
        )
    return _client


class _SupabaseProxy:
    """Defer create_client until first use so module import never fails without env vars."""
    def __getattr__(self, name: str):
        return getattr(_get_client(), name)


supabase: Client = _SupabaseProxy()  # type: ignore
