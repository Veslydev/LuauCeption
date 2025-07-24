local runtime_init = require("@self/runtime")

local polyfill_init = require("./polyfill")
local utils_init = require("./utils")

return function()
    local utils, utils_ready = utils_init()
    local polyfill, polyfill_ready = polyfill_init(utils)

    local RuntimeInstance = runtime_init({
        env = {
            func_list = {
                __cxa_throw = polyfill.__cxa_throw,
                invoke_vii = polyfill.invokeHandler(1),
                _abort_js = polyfill._abort_js,
                emscripten_date_now = polyfill.emscripten_date_now,
                _tzset_js = utils.stub("_tzset_js", 0),
                _localtime_js = polyfill._localtime_js,
                _gmtime_js = polyfill._gmtime_js,
                emscripten_resize_heap = polyfill.emscripten_resize_heap,
                _emscripten_throw_longjmp = polyfill._emscripten_throw_longjmp,
                _setitimer_js = polyfill._setitimer_js,
                _emscripten_runtime_keepalive_clear = polyfill._emscripten_runtime_keepalive_clear,
            }
        },
        wasi_snapshot_preview1 = {
            func_list = {
                clock_time_get = polyfill.clock_time_get,
                fd_write = polyfill.fd_write,
                proc_exit = polyfill.proc_exit,
            }
        }
    })

    local rt, memory_at_0, cfns, INDIRECT_FUNCTIONS =
        RuntimeInstance.rt,
        RuntimeInstance.memory_list.memory,
        RuntimeInstance.func_list,
        RuntimeInstance.table_list.__indirect_function_table

    polyfill_ready(rt, memory_at_0, cfns, INDIRECT_FUNCTIONS)
    utils_ready(rt, memory_at_0, cfns, INDIRECT_FUNCTIONS)
    return rt, memory_at_0, cfns, INDIRECT_FUNCTIONS, utils, polyfill
end