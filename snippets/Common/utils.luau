local CException = {} do
    local CExcInternal = {}
    CExcInternal.__index = CExcInternal

    function CExcInternal:_UndecoratedName()
        local name_ptr = rt.load.i32(memory_at_0, self.ptr + 4);
        return rt.load.string(memory_at_0, name_ptr, cfns.strlen(name_ptr))
    end

    function CExcInternal:vfptr()
        local vfptr = rt.load.i32(memory_at_0, self.ptr);
        return vfptr
    end

    function CException.new(excPtr)
        local self = {}
        self.excPtr = excPtr
        self.ptr = excPtr - 24

        return setmetatable(self, CExcInternal)
    end
end

local function cstr(value: string): number
    local str_len = #value
    local str_ptr = cfns.malloc(str_len + 1)
    rt.store.string(memory_at_0, str_ptr, value)
    rt.store.i32_n8(memory_at_0, str_ptr + str_len, 0)

    return str_ptr
end

local function stub(name: string, ret: any)
    return function(...)
        if (STUB_WARN) then
            print(`[WARN]: stub function '{name}' called`)
        end

        return ret
    end
end

local __LONGJMP_THROW_SIGN = newproxy(false)
local function invokeHandler(index: number)
    return function(fnIndex: number, ...)
        local stack_ptr = cfns.emscripten_stack_get_current()
        local err, stacktrace = "N/A", "N/A"
        local success = xpcall(INDIRECT_FUNCTIONS.data[fnIndex], function(_err)err,stacktrace = _err,debug.traceback()end, ...)
        if success then
            return
        end

        cfns._emscripten_stack_restore(stack_ptr)
        assert(err == __LONGJMP_THROW_SIGN, `{err}\n\ninvoke stacktrace:\n{stacktrace}`)
        cfns.setThrew(1, 0)
    end
end

local function insertCFunction(func: (...any) -> (...any)): number
    local ptr = #INDIRECT_FUNCTIONS.data + 1
    INDIRECT_FUNCTIONS.data[ptr] = func

    return ptr
end
