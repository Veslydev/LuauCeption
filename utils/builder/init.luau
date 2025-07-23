local fs = require("@lune/fs")
local process = require("@lune/process")
local regex = require("@lune/regex")
local task = require("@lune/task")

local LUAU_GIT_HASH, LUAU_GIT_TAG = (function()
    local GIT_EXEC_OPTIONS = {
        cwd = "./luau"
    }

    local git_hash_proc = process.exec(
        "git", {"rev-parse", "HEAD"},
        GIT_EXEC_OPTIONS
    )
    if not git_hash_proc.ok then
        return error("Failed to get git commit hash of luau submodule!")
    end

    local git_tag_proc = process.exec(
        "git", {"describe", "--tags"},
        GIT_EXEC_OPTIONS
    )
    if not git_tag_proc.ok then
        return error("Failed to get git tag name of luau submodule!")
    end

    return string.gsub(git_hash_proc.stdout, "[\r\n]+", ""),
        (string.gsub(git_tag_proc.stdout, "[\r\n]+", "") or "UNKNOWN_TAG")
end)()

type BuildVariant = "Compiler" | "VM" | "Full"
type SnippetOrder = {any}
type VariantSnippetInstructions = {
    runtime: SnippetOrder,
    entrypoint: SnippetOrder
}

local WASYNTH_EXEC = "./utils/wasm2luau"
local WASM_OUTPUT_DIR = "./build"
local BUILD_DIR = "./output"

local VARIANT_PREFIX = "Luau.LuauCeption"

local function createHeaderSnippet(variant: BuildVariant): string
    local result = {
        `--// LuauCeption - {variant} Variant`,
        `--// Build from Luau {LUAU_GIT_TAG} ({LUAU_GIT_HASH})`,
    }
    return table.concat(result, "\n")
end

local VARIANT_BUILD_SNIPPET_ORDER: {[string]: VariantSnippetInstructions} = {
    ["Compiler"] = {
        ["runtime"] = {
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("Compiler")},
            {"putfile", "Common/vector3_compat.luau"},
        },
        ["entrypoint"] = {
            {"putfile", "Compiler/init.luau"},
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("Compiler")},
            
            {"goto", "start", "--@@UTILS@@"},
            {"removeline"},
            {"putfile", "Common/utils.luau"},

            {"goto", "start", "--@@FLAGS@@"},
            {"removeline"},
            {"putfile", "Common/flags.luau"},
        },
    },
    ["VM"] = {
        ["runtime"] = {
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("VM")},
            {"putfile", "Common/vector3_compat.luau"},
        },
        ["entrypoint"] = {
            {"putfile", "VM/init.luau"},
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("VM")},
            
            {"goto", "start", "--@@VM_COMMONS@@"},
            {"removeline"},
            {"putfile", "VM/commons.luau"},

            {"goto", "start", "--@@UTILS@@"},
            {"removeline"},
            {"putfile", "Common/utils.luau"},

            {"goto", "start", "--@@FLAGS@@"},
            {"removeline"},
            {"putfile", "Common/flags.luau"},

            {"goto", "start", "--@@MACROS@@"},
            {"removeline"},
            {"putfile", "VM/luau_macros.luau"},
        },
    },
    ["Full"] = {
        ["runtime"] = {
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("Full")},
            {"putfile", "Common/vector3_compat.luau"},
        },
        ["entrypoint"] = {
            {"putfile", "Full/init.luau"},
            {"goto", "end", "--!optimize 2"},
            {"putstring", createHeaderSnippet("Full")},
            
            {"goto", "start", "--@@VM_COMMONS@@"},
            {"removeline"},
            {"putfile", "VM/commons.luau"},

            {"goto", "start", "--@@UTILS@@"},
            {"removeline"},
            {"putfile", "Common/utils.luau"},

            {"goto", "start", "--@@FLAGS@@"},
            {"removeline"},
            {"putfile", "Common/flags.luau"},

            {"goto", "start", "--@@MACROS@@"},
            {"removeline"},
            {"putfile", "VM/luau_macros.luau"},
        },
    },
}

local function getAbsolutePath(relative_path: string): string
    return `{process.cwd}/{relative_path}`
end

local function processSnippetOrder(snippet_orders: {{string}}, to_process: string): string
    local current_position = 0
    local result = to_process

    for _, order in snippet_orders do
        local command = order[1]

        if command == "goto" then
            local pattern = regex.new(order[3]):find(result)
            if not pattern then
                print(`Cannot find pattern '{order[3]}' on goto command`)
                continue
            end

            local position_mode = order[2]
            if position_mode == "start" then
                current_position = pattern.start
            elseif position_mode == "end" then
                current_position = pattern.finish + 1
            end
        elseif command == "remove_to_end" then
            result = string.sub(result, 1, current_position - 1)
        elseif command == "removeline" then
            local str_start = string.sub(result, 1, current_position)
            local str_end = string.sub(result, current_position)
            local pre = string.match(str_start, "^(.*)\n[^\n]*$") or ""
            local post = string.match(str_end, "^[^\n]*\n?(.*)$") or ""
            local corrected_pos = string.match(string.sub(result, 1, current_position - 1), ".*()\n")

            result = pre .. post
            current_position = corrected_pos or current_position
        elseif command == "putstring" or command == "putfile" then
            local content = order[2]
            if command == "putfile" then
                local file_path = getAbsolutePath(`./snippets/{order[2]}`)
                if not fs.isFile(file_path) then
                    return error(`Cannot find assigned file '{order[2]}' on putfile command!`)
                end

                content = fs.readFile(file_path)
            end

            local content_len = (utf8.len(content) :: number) + 1
            local str_start = string.sub(result, 1, current_position)
            local str_end = string.sub(result, current_position)

            result = str_start .. content .. str_end
            current_position += content_len
        end
    end
    return result
end

local function createBuildVariant(variant: BuildVariant)
    local snippet_orders = VARIANT_BUILD_SNIPPET_ORDER[variant]
    if not snippet_orders then
        return error(`Invalid variant type '{variant}'`)
    end

    local variant_id = `{VARIANT_PREFIX}.{variant}`
    local wasm_file = getAbsolutePath(`{WASM_OUTPUT_DIR}/{variant_id}.wasm`)
    local variant_container = getAbsolutePath(`{BUILD_DIR}/{variant_id}`)

    if not fs.isFile(wasm_file) then
        return error(`Build file of variant '{variant}' not found!`)
    end

    local wasynth_proc = process.create(WASYNTH_EXEC, {wasm_file})
    local wasynth_output = wasynth_proc.stdout:readToEnd()
    if not wasynth_proc:status().ok then
        return error(`Failed to transpile WASM output of variant '{variant}'`)
    end
    print(`Variant '{variant}' got wasm transpiled to luau successfully.`)

    if not fs.isDir(variant_container) then
        fs.writeDir(variant_container)
    end

    local processed_runtime = processSnippetOrder(snippet_orders.runtime, wasynth_output)
    if not processed_runtime then
        return error(`Failed to process runtime of variant '{variant}'`)
    end
    print(`Successfully processed transpiled runtime of variant '{variant}'!`)
    fs.writeFile(`{variant_container}/runtime.luau`, processed_runtime)

    local processed_entrypoint = processSnippetOrder(snippet_orders.entrypoint, "")
    if not processed_entrypoint then
        return error(`Failed to process variant '{variant}'`)
    end
    print(`Successfully processed entrypoint of variant '{variant}'!`)
    fs.writeFile(`{variant_container}/init.luau`, processed_entrypoint)
    return
end

do
    if not fs.isDir(getAbsolutePath(BUILD_DIR)) then
        fs.writeDir(getAbsolutePath(BUILD_DIR))
    end

    for _, variant in {"Compiler", "VM", "Full"} do
        createBuildVariant(variant)
    end
end
