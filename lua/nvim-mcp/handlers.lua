local M = {}

-- Default handler implementations
M._defaults = {}

---@param params_raw string JSON-encoded TextDocumentPositionParams
---@return string JSON-encoded result or error
M._defaults.navigate = function(params_raw)
    local params = vim.json.decode(params_raw)

    -- Convert to 1-based row for Vim (col is already 0-based)
    params.position.line = params.position.line + 1

    -- Function to navigate to file by URI
    local function navigate_to_file(file_uri)
        -- Convert URI to file path
        local file_path = vim.uri_to_fname(file_uri)

        -- Check if file exists first
        if vim.fn.filereadable(file_path) == 0 then
            return vim.json.encode({ err_msg = "File not found or not readable: " .. file_path })
        end

        -- Check if the file is already open in a buffer
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(buf) then
                local bufname = vim.api.nvim_buf_get_name(buf)
                local buf_path = vim.fn.fnamemodify(bufname, ":p")
                local target_path = vim.fn.fnamemodify(file_path, ":p")
                if buf_path == target_path then
                    vim.cmd("buffer " .. buf)
                    return true
                end
            end
        end

        -- If not open, edit the file
        vim.cmd("edit " .. vim.fn.fnameescape(file_path))
        return true
    end

    local result = navigate_to_file(params.textDocument.uri)
    if type(result) == "string" then
        -- navigate_to_file returned JSON encoded error
        return result
    end

    -- Set the cursor position
    local current_buf = vim.api.nvim_get_current_buf()

    -- Set cursor position
    vim.api.nvim_win_set_cursor(0, { params.position.line, params.position.character })

    -- Return success information
    local current_bufname = vim.api.nvim_buf_get_name(current_buf)
    local line = vim.api.nvim_get_current_line()
    return vim.json.encode({
        result = {
            success = true,
            buffer_name = current_bufname,
            line = line,
        },
    })
end

---@param client_name string LSP client name
---@param workspace_edit_raw string JSON-encoded WorkspaceEdit
---@return string JSON-encoded result or error
M._defaults.lsp_apply_edit = function(client_name, workspace_edit_raw)
    local clients = vim.lsp.get_clients()
    local client
    for _, v in ipairs(clients) do
        if v.name == client_name then
            client = v
        end
    end
    if client == nil then
        return vim.json.encode({
            err_msg = string.format("LSP client %s not found", vim.json.encode(client_name)),
        })
    end

    local workspace_edit = vim.json.decode(workspace_edit_raw)
    local position_encoding = client.offset_encoding or "utf-16"
    vim.lsp.util.apply_workspace_edit(workspace_edit, position_encoding)
    return vim.json.encode({
        result = vim.NIL,
    })
end

---@param uri string Document URI
---@param edits_raw string JSON-encoded array of TextEdit
---@param auto_save boolean Whether to save after applying edits
---@return string JSON-encoded result or error
M._defaults.edit_buffer = function(uri, edits_raw, auto_save)
    -- Parse the edits JSON
    local edits = vim.json.decode(edits_raw)

    -- Get buffer number from URI
    local bufnr = vim.uri_to_bufnr(uri)

    -- Check if buffer is loaded
    if not vim.api.nvim_buf_is_loaded(bufnr) then
        return vim.json.encode({
            err_msg = string.format("Buffer for URI %s is not loaded", uri),
        })
    end

    -- Get buffer name/path
    local buffer_name = vim.api.nvim_buf_get_name(bufnr)

    -- Sort edits in reverse order (last line first, last character first)
    -- This prevents range invalidation as we apply edits
    table.sort(edits, function(a, b)
        if a.range.start.line ~= b.range.start.line then
            return a.range.start.line > b.range.start.line
        end
        return a.range.start.character > b.range.start.character
    end)

    -- Apply each edit
    local edits_applied = 0
    for _, edit in ipairs(edits) do
        local start_line = edit.range.start.line
        local start_char = edit.range.start.character
        local end_line = edit.range["end"].line
        local end_char = edit.range["end"].character
        local new_text = edit.newText

        -- Split new_text into lines
        local new_lines = vim.split(new_text, "\n", { plain = true })

        -- Apply the edit using nvim_buf_set_text
        -- This integrates with undo/redo automatically
        local success, err = pcall(vim.api.nvim_buf_set_text, bufnr, start_line, start_char, end_line, end_char, new_lines)

        if not success then
            return vim.json.encode({
                err_msg = string.format("Failed to apply edit at line %d, character %d: %s", start_line, start_char, err),
            })
        end

        edits_applied = edits_applied + 1
    end

    -- Optionally save the buffer
    local saved = false
    if auto_save then
        -- Use nvim_buf_call to execute :write in the context of the buffer
        local success, err = pcall(function()
            vim.api.nvim_buf_call(bufnr, function()
                vim.cmd("write")
            end)
        end)

        if success then
            saved = true
        else
            return vim.json.encode({
                err_msg = string.format("Failed to save buffer: %s", err),
            })
        end
    end

    -- Return success result
    return vim.json.encode({
        result = {
            buffer_id = bufnr,
            file_path = buffer_name ~= "" and buffer_name or vim.NIL,
            saved = saved,
            edits_applied = edits_applied,
        },
    })
end

-- Active handlers (starts as copy of defaults)
M._handlers = vim.tbl_deep_extend("force", {}, M._defaults)

--- Call a handler with the provided arguments
---@param handler_name string Name of the handler to call
---@param ... any Arguments to pass to the handler
---@return string JSON-encoded result or error
function M.call(handler_name, ...)
    local handler = M._handlers[handler_name]
    if not handler then
        return vim.json.encode({
            err_msg = "Handler not found: " .. handler_name
        })
    end

    -- Execute with error handling
    local success, result = pcall(handler, ...)
    if success then
        return result
    else
        return vim.json.encode({
            err_msg = "Handler execution failed: " .. tostring(result)
        })
    end
end

--- Override a specific handler with a custom implementation
---@param handler_name string Name of the handler to override
---@param handler_fn function Custom handler implementation
function M.override(handler_name, handler_fn)
    if not M._defaults[handler_name] then
        vim.notify(
            string.format("Warning: Overriding unknown handler '%s'", handler_name),
            vim.log.levels.WARN
        )
    end
    M._handlers[handler_name] = handler_fn
end

--- Reset a handler to its default implementation
---@param handler_name string Name of the handler to reset
function M.reset(handler_name)
    if M._defaults[handler_name] then
        M._handlers[handler_name] = M._defaults[handler_name]
    else
        vim.notify(
            string.format("Cannot reset unknown handler '%s'", handler_name),
            vim.log.levels.ERROR
        )
    end
end

--- Get list of available default handlers
---@return string[] List of handler names
function M.list_handlers()
    local names = {}
    for name, _ in pairs(M._defaults) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

local DiagSummary = {
	bufnr = 0,
}
DiagSummary.__index = DiagSummary

---@classDiagSummary
function DiagSummary:new(buf)
	return setmetatable({
		bufnr = buf,
		name = vim.api.nvim_buf_get_name(buf),
		error = 0,
		warn = 0,
		info = 0,
		hint = 0,
	}, DiagSummary)
end

---@param d:diagnostic diagnostic
function DiagSummary:add(d)
	if d == vim.diagnostic.severity.HINT then
		self.hint = self.hint + 1
	elseif d == vim.diagnostic.severity.INFO then
		self.info = self.info + 1
	elseif d == vim.diagnostic.severity.INFO then
		self.info = self.info + 1
	elseif d == vim.diagnostic.severity.INFO then
		self.info = self.info + 1
	end
end

function M.diagnostic_summary()
	local diags = vim.diagnostic.get()
	local summaries = {}
	for d in diags do
		if summaries[d.bufnr] == nil then
			summaries[d.bufnr] = DiagSummary:new(d.bufnr)
		end
		summaries[d.bufnr]:add(d)
	end
	local ret = {}
	for _i, v in ipairs(summaries) do
		table.insert(ret, v)
	end
	return ret
end

return M
