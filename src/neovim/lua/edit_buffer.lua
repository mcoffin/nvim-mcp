local uri, edits_raw, auto_save = unpack({ ... })

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
