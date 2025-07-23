--!optimize 2
local STUB_WARN = false

--@@VM_COMMONS@@

local function luau_run(bc: string, chunkName: string?, safeEnv: boolean?): boolean
    --// Bytecode
    local bcPtr = cstr(bc)

    --// Chunk name
    local cnPtr = cstr(chunkName or "LuauCeptionChunk")

    --// State setup
    local L = cfns.luaL_newstate()
    cfns.luaL_openlibs(L);
    if (safeEnv) then cfns.luaL_sandbox(L) end

    --// Load bytecode
    local ldRes = cfns.luau_load(L, cnPtr, bcPtr, #bc, 0)

    --// Cleanup unused stuff
    cfns.free(bcPtr)
    cfns.free(cnPtr)

    --// Check if load succeded
    if (ldRes ~= 0) then cfns.lua_close(L) end
    assert(ldRes == 0, "failed to load luau bytecode")

    --// Call function
    local clRes = cfns.lua_pcall(L, 0, 0, 0)

    --// Cleanup state
    cfns.lua_close(L)

    return clRes == 0
end

local function luau_load(bc: string, chunkName: string?, safeEnv: boolean?): () -> (boolean)
    return function()
        return luau_run(bc, chunkName, safeEnv)
    end
end

--@@FLAGS@@

--@@MACROS@@

return {
	luau_run = luau_run,
    luau_load = luau_load,
    luau_setflag = luau_setflag,
    luau_setallflags = luau_setallflags,
    luau_resetflags = luau_resetflags,
    macros = macros,
	wasm = {
		rt = rt,
		cfns = cfns,
		indirect_function_table = INDIRECT_FUNCTIONS,
		memory = memory_at_0,
        insertCFunction = insertCFunction,
        cstr = cstr
	}
}
