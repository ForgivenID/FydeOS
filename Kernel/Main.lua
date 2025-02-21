-- Main.lua
KERNEL_VERSION = "FydesLoader-ScrapComputers-Lua_v1.0.1a"
KERNEL_NAME = "KERNEL"

local function enum(keys)
    local Enum = {}
    for _, value in ipairs(keys) do
        Enum[value] = {}
    end
    return Enum
end

local function extend(child, parent)
    setmetatable(child, { __index = parent })
end

local function wrap_into(sm_components, wrapper_class)
    if not sm_components then
        error("wrap exception for " .. wrapper_class._class)
    end

    local wrapped = {}
    for idx, component in pairs(sm_components) do
        wrapped[idx] = component:is_wrapped() and component or wrapper_class:new(component)
    end
    return wrapped
end

local function concat_lists(t1, t2)
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end
    return t1
end

local function shallow_copy(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

local function deep_copy(obj, seen)
    if type(obj) ~= "table" then return obj end
    if seen and seen[obj] then return seen[obj] end

    local res = setmetatable({}, getmetatable(obj))
    seen = seen or {}
    seen[obj] = res

    for k, v in pairs(obj) do
        res[deep_copy(k, seen)] = deep_copy(v, seen)
    end
    return res
end

local function getId(t)
    return string.format("%p", t)
end

-- TerminalWrapper
TerminalWrapper = {}
function TerminalWrapper:new(terminal)
    local private = {
        terminal = terminal,
        inputs_buffer = {},
        buffer = {},
        draw_buffer = {},
        redraw_flag = true,
        is_supressed = false,
        wrapped = true
    }

    local public = {
        _id = getId(terminal)
    }

    function public:is_wrapped()
        return private.wrapped
    end

    function public:clear()
        private.buffer = {}
        private.draw_buffer = {}
        private.redraw_flag = true
    end

    function public:update()
        if not private.terminal then return end

        if private.redraw_flag then
            private.redraw_flag = false
            private.terminal.clear()
            private.terminal.send("--- [" .. KERNEL_VERSION .. "] DEBUG ---")
            for _, entry in ipairs(private.buffer) do
                private.terminal.send(entry.msg)
            end
        end

        for _, entry in ipairs(private.draw_buffer) do
            private.terminal.send(entry.msg)
            table.insert(private.buffer, entry)
        end
        private.draw_buffer = {}

        while private.terminal.receivedInputs() do
            table.insert(private.inputs_buffer, private.terminal.getInput())
        end
    end

    function public:input(callback_id)
        local input = private.inputs_buffer[callback_id or -1]
        private.inputs_buffer[callback_id or -1] = nil
        return input
    end

    function public:send(msg, callback_id)
        if type(msg) ~= "string" then
            return nil, "TerminalWrapper:send() - Expected string, got " .. type(msg)
        end
        table.insert(private.draw_buffer, { msg = msg, cb_id = callback_id or -1 })
    end

    function public:insert(msg, index, callback_id)
        if type(msg) ~= "string" then
            return false, "TerminalWrapper:insert() - Expected string, got " .. type(msg)
        end

        callback_id = callback_id or -1
        local target_buffer, buffer_index

        if index <= #private.buffer then
            target_buffer = private.buffer
            buffer_index = index
        elseif index <= #private.buffer + #private.draw_buffer then
            target_buffer = private.draw_buffer
            buffer_index = index - #private.buffer
        else
            return false, "TerminalWrapper:insert() - Index out of bounds"
        end

        if target_buffer[buffer_index] and target_buffer[buffer_index].cb_id == callback_id then
            return false, "TerminalWrapper:insert() - Incompetent line overwrite"
        end

        target_buffer[buffer_index] = { msg = msg, cb_id = callback_id }
        private.redraw_flag = true
        return true
    end

    setmetatable(public, self)
    self.__index = self; return public
end

-- TerminalManager
TerminalManager = {}
function TerminalManager:new(terminals)
    local private = {
        terminals = {},
        given_out = {}
    }

    local public = {}

    for _, wrapped_terminal in pairs(wrap_into(terminals, TerminalWrapper)) do
        local _id = wrapped_terminal._id
        private.terminals[_id] = wrapped_terminal
        wrapped_terminal:send("[" .. KERNEL_NAME .. "] CONNECTED TO TERMINAL MANAGER AS " .. _id)
        wrapped_terminal:send("NOT BOUND TO ANY PROCESS")
        wrapped_terminal:update()
    end

    function public:update()
        for _, t in pairs(private.terminals) do
            t:update()
        end
    end

    function public:bind_terminal(p_id)
        for _id, t in pairs(private.terminals) do
            if not private.given_out[_id] then
                local tws = TerminalWrapper:new(t)
                tws:clear()
                private.given_out[_id] = { p_id = p_id, tws = tws }
                return tws
            end
        end
        return nil
    end

    function public:unbind_terminal(p_id)
        for _id, entry in pairs(private.given_out) do
            if entry.p_id == p_id then
                private.given_out[_id] = nil
                break
            end
        end
    end

    setmetatable(public, self)
    self.__index = self; return public
end

-- DisplayManager
DisplayManager = {}
function DisplayManager:new(display)
    local private = { display = display, wrapped = true }
    local public = {}

    function public:is_wrapped()
        return private.wrapped
    end

    setmetatable(public, self)
    self.__index = self; return public
end

Process = {}
function Process:new(name, source, parent, kernel_ref)
    private = {}
    public = {}

    private.name = name
    private.source_file = source
    private.parent = parent
    private.children = {}

    private.chunk_pointer = nil
    private.error_stack = {}
    private.sleep_timer = 0
    private.kernel = kernel_ref




    function private:sleep(ticks)
        public.sleep_timer = ticks
    end

    private.environment = {
        assert = assert,
        pcall = pcall,
        xpcall = xpcall,
        error = error,

    }

    for k, v in pairs(private.kernel.system_environment) do
        private.environment[k] = v
    end

    setmetatable(public, self)
    self.__index = self; return public
end
