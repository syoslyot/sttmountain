import os
from supabase import create_client, Client
from dotenv import load_dotenv

load_dotenv()
load_dotenv(".env.local", override=True)

SUPABASE_URL  = os.environ["SUPABASE_URL"]
SUPABASE_ANON = os.environ["SUPABASE_ANON_KEY"]
supabase: Client = create_client(SUPABASE_URL, SUPABASE_ANON)
STORAGE_BASE = f"{SUPABASE_URL}/storage/v1/object/public"
