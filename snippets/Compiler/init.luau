--!optimize 2
local STUB_WARN = false

local task = task or require("@lune/task")
local RuntimeInitialize = require("@self/runtime")
local RuntimeInstance;
local rt, memory_at_0, cfns, INDIRECT_FUNCTIONS

--@@UTILS@@

do
    local __TIMERS = {}
    local __EXIT_STATUS = nil
    local __ABORT_WASM = false
    local __NO_EXIT_RUNTIME = true
    local __RUNTIME_KEEPALIVE_COUNTER = 0

    local function proc_exit(code)
        __EXIT_STATUS = code
        if (not (__NO_EXIT_RUNTIME or __RUNTIME_KEEPALIVE_COUNTER > 0)) then
            __ABORT_WASM = true
        end

        assert(false, `ExitStatus: Program exited with code ${code}`)
    end

    local function _abort_js(reason)
        assert(false, `Aborted({reason})`)
    end

    local function __cxa_throw(ptr, type, destructor)
        local info = CException.new(ptr)
        assert(false, `exception occured in c: {info:_UndecoratedName()} ({info:vfptr()})`)
    end

    local function emscripten_resize_heap(_requestedSize)
        assert(false, "OOM")
    end

    local function _emscripten_runtime_keepalive_clear()
        __NO_EXIT_RUNTIME = false
        __RUNTIME_KEEPALIVE_COUNTER = 0
        return
    end

    local function _setitimer_js(which, timeoutMs)
        if (not task) then
            print("program is using _setitimer_js but task library not found, timers will NOT work.")
            return 0
        end

        if (__TIMERS[which]) then
            task.cancel(__TIMERS[which].thread)
            __TIMERS[which] = nil
        end
        if (not timeoutMs or timeoutMs == 0) then
            return 0
        end

        local thread = task.delay(function()
            __TIMERS[which] = nil
            if (__ABORT_WASM) then
                return
            end

            local success, err = pcall(function()
                cfns._emscripten_timeout(which, os.clock())
                if (__NO_EXIT_RUNTIME or __RUNTIME_KEEPALIVE_COUNTER > 0) then
                    return
                end

                local exit_success, exit_err = pcall(proc_exit, __EXIT_STATUS)
                if exit_success then
                    return
                end

                if (string.match(exit_err, "ExitStatus:") ~= nil or exit_err == "unwind") then
                    return __EXIT_STATUS
                end
                assert(false, exit_err)
            end)

            if (not success) then
                if (string.match(err, "ExitStatus:") ~= nil or err == "unwind") then
                    return
                end
                assert(false, err)
            end
        end, timeoutMs / 1000)

        __TIMERS[which] = { thread = thread, timeoutMs = timeoutMs }
        return 0
    end

    RuntimeInstance = RuntimeInitialize({
        env = {
            func_list = {
                _abort_js = _abort_js,
                __cxa_throw = __cxa_throw,
                emscripten_resize_heap = emscripten_resize_heap,
                _emscripten_runtime_keepalive_clear = _emscripten_runtime_keepalive_clear,
                _setitimer_js = _setitimer_js,
            }
        },
        wasi_snapshot_preview1 = {
            func_list = {
                proc_exit = proc_exit
            }
        }
    })
    rt, memory_at_0, cfns, INDIRECT_FUNCTIONS =
        RuntimeInstance.rt,
        RuntimeInstance.memory_list.memory,
        RuntimeInstance.func_list,
        RuntimeInstance.table_list.__indirect_function_table
end

local function luau_compile(src: string, optLevel: number?, dbgLevel: number?, typInfLevel: number?, covLevel: number?)
    --// Source string
    local srcPtr = cstr(src)

    --// Struct lua_CompileOptions (see luau/Compiler/include/luacode.h)
    local compileOptsPtr = cfns.malloc(36)
    rt.store.i32(memory_at_0, compileOptsPtr + 0, optLevel or 1) --// int optimizationLevel
    rt.store.i32(memory_at_0, compileOptsPtr + 4, dbgLevel or 1) --// int debugLevel
    rt.store.i32(memory_at_0, compileOptsPtr + 8, typInfLevel or 0) --// int typeInfoLevel
    rt.store.i32(memory_at_0, compileOptsPtr + 12, covLevel or 0) --// int coverageLevel
    rt.store.i32(memory_at_0, compileOptsPtr + 16, 0) --// const char* vectorLib
    rt.store.i32(memory_at_0, compileOptsPtr + 20, 0) --// const char* vectorCtor
    rt.store.i32(memory_at_0, compileOptsPtr + 24, 0) --// const char* vectorType
    rt.store.i32(memory_at_0, compileOptsPtr + 28, 0) --// const char* const* mutableGlobals
    rt.store.i32(memory_at_0, compileOptsPtr + 32, 0) --// const char* const* userdataTypes

    --// Bytecode size
    local bcSizePtr = cfns.malloc(8)

    --// Compile
    local bcPtr = cfns.luau_compile(srcPtr, #src, compileOptsPtr, bcSizePtr)
    local bcSize = rt.load.i32(memory_at_0, bcSizePtr)
    local bc = rt.load.string(memory_at_0, bcPtr, bcSize)

    --// Cleanup
    cfns.free(srcPtr)
	cfns.free(bcPtr)
    cfns.free(bcSizePtr)
    cfns.free(compileOptsPtr)

    return bc, bcSize
end

--@@FLAGS@@

return {
	luau_compile = luau_compile,
    luau_setflag = luau_setflag,
    luau_setallflags = luau_setallflags,
    luau_resetflags = luau_resetflags,
	wasm = {
		rt = rt,
		cfns = cfns,
		indirect_function_table = INDIRECT_FUNCTIONS,
		memory = memory_at_0,
        insertCFunction = insertCFunction,
        cstr = cstr
	}
}
