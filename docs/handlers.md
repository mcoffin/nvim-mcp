# Handler Customization

The nvim-mcp plugin provides customizable handlers for certain MCP tool operations. This allows you to modify the behavior of tools without recompiling the Rust binary.

## Available Handlers

The following handlers can be overridden:

- **`navigate`** - Controls how the MCP navigate tool positions the cursor in files
- **`lsp_apply_edit`** - Controls how LSP workspace edits are applied
- **`edit_buffer`** - Controls how direct buffer edits are applied

## Overriding Handlers

Handlers can be overridden via the `setup()` function's `handlers` option:

```lua
require('nvim-mcp').setup({
    handlers = {
        navigate = function(params_raw)
            -- Custom navigate implementation
            -- params_raw is a JSON string containing TextDocumentPositionParams
            local params = vim.json.decode(params_raw)

            -- Your custom logic here
            -- Must return a JSON-encoded string
            return vim.json.encode({
                result = { success = true }
            })
        end
    }
})
```

## Handler Signatures

### navigate

**Input**: JSON-encoded `TextDocumentPositionParams`
```lua
{
    textDocument = {
        uri = "file:///path/to/file.txt"
    },
    position = {
        line = 10,      -- 0-based (already converted from LSP)
        character = 5   -- 0-based
    }
}
```

**Output**: JSON-encoded result or error
```lua
-- Success
{
    result = {
        success = true,
        buffer_name = "/path/to/file.txt",
        line = "content of the line"
    }
}

-- Error
{
    err_msg = "File not found"
}
```

### lsp_apply_edit

**Input**: Two parameters
1. `client_name` (string) - Name of the LSP client
2. `workspace_edit_raw` (string) - JSON-encoded LSP WorkspaceEdit

**Output**: JSON-encoded result or error
```lua
-- Success
{
    result = vim.NIL
}

-- Error
{
    err_msg = "LSP client not found"
}
```

### edit_buffer

**Input**: Three parameters
1. `uri` (string) - Document URI
2. `edits_raw` (string) - JSON-encoded array of TextEdit
3. `auto_save` (boolean) - Whether to save after applying edits

**Output**: JSON-encoded result or error
```lua
-- Success
{
    result = {
        buffer_id = 1,
        file_path = "/path/to/file.txt",
        saved = true,
        edits_applied = 3
    }
}

-- Error
{
    err_msg = "Buffer not loaded"
}
```

## Example: Custom Navigate Behavior

Open files in a vertical split instead of the current window:

```lua
require('nvim-mcp').setup({
    handlers = {
        navigate = function(params_raw)
            local params = vim.json.decode(params_raw)

            -- Convert to 1-based line for Vim
            params.position.line = params.position.line + 1

            -- Extract file path from URI
            local file_path = vim.uri_to_fname(params.textDocument.uri)

            -- Open in vertical split
            vim.cmd('vsplit ' .. vim.fn.fnameescape(file_path))

            -- Set cursor position
            vim.api.nvim_win_set_cursor(0, {
                params.position.line,
                params.position.character
            })

            return vim.json.encode({
                result = {
                    success = true,
                    buffer_name = vim.api.nvim_buf_get_name(0),
                    line = vim.api.nvim_get_current_line()
                }
            })
        end
    }
})
```

## Example: Custom Edit Buffer with Confirmation

Add a confirmation prompt before applying edits:

```lua
require('nvim-mcp').setup({
    handlers = {
        edit_buffer = function(uri, edits_raw, auto_save)
            local edits = vim.json.decode(edits_raw)

            -- Show confirmation
            local choice = vim.fn.confirm(
                string.format("Apply %d edits?", #edits),
                "&Yes\n&No",
                1
            )

            if choice ~= 1 then
                return vim.json.encode({
                    err_msg = "Edit cancelled by user"
                })
            end

            -- Use default handler logic
            local handlers = require('nvim-mcp.handlers')
            return handlers._defaults.edit_buffer(uri, edits_raw, auto_save)
        end
    }
})
```

## Accessing Default Handlers

You can access the default handler implementations:

```lua
local handlers = require('nvim-mcp.handlers')

-- Get default navigate handler
local default_navigate = handlers._defaults.navigate

-- Reset a handler to default
handlers.reset('navigate')

-- List all available handlers
local handler_names = handlers.list_handlers()
```

## Error Handling

Handlers should use `pcall` for error handling and return proper error messages:

```lua
navigate = function(params_raw)
    local success, params = pcall(vim.json.decode, params_raw)
    if not success then
        return vim.json.encode({
            err_msg = "Failed to parse parameters: " .. tostring(params)
        })
    end

    -- Your handler logic...
end
```

## Notes

- Handlers are called from Rust via `require('nvim-mcp.handlers').call('handler_name', ...)`
- All handlers must return a JSON-encoded string
- Handler parameter parsing is done by the handler itself (gives you flexibility)
- Changes to handlers require reloading your Neovim configuration
- The handlers module automatically wraps calls in `pcall` for safety
