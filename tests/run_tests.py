"""Run with Python + lupa. The optional local runtime stays outside the mod."""
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(tempfile.gettempdir()) / "ea_match_lua_tests"))
from lupa.lua53 import LuaRuntime

json_dir = ROOT.parents[1] / "resources" / "scripts"
if not (json_dir / "json.lua").exists():
    raise SystemExit("Place ea_match in the game's mods directory to use its json.lua.")
for script in ("test_rules.lua", "mock_game.lua"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ROOT = ROOT.as_posix()
    lua.execute("package.path = ... .. '/?.lua;' .. package.path", json_dir.as_posix())
    for path in [ROOT / "main.lua", *ROOT.joinpath("scripts").glob("*.lua")]:
        lua.execute("assert(load(...))", path.read_text(encoding="utf-8"))
    lua.execute((ROOT / "tests" / script).read_text(encoding="utf-8"))
print("Lua 5.3 syntax: all production files passed")
