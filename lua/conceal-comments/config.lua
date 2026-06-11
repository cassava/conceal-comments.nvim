--- Configuration

local M = {}

---@class ConcealComments.GutterConfig
---@field enabled "always"|"collapse"|"placeholder" When to enable showing signs
---@field icon string Icon string to use for signs
---@field icon_above string Icon string to use for signing comments above line
---@field icon_below string Icon string to use for signing comments below line
---@field highlight string Highlight class to use

---@class ConcealComments.Config
---@field node_types string[] Tree-sitter node types to treat as comments.
---@field prefer_highlight boolean Use @comment highlight group instead of node searching (more efficient).
---@field mode "collapse"|"placeholder" How to display concealed comments.
---@field swallow_empty_lines_before boolean Remove preceding empty lines around comment blocks.
---@field swallow_empty_lines_after boolean Remove trailing empty lines around comment blocks.
---@field concealcursor string|nil Set concealcursor to keep lines hidden in all modes (e.g. "nvic").
---@field gutter ConcealComments.GutterConfig Settings for displaying signs in the gutter.

---@type ConcealComments.Config
M.defaults = {
    node_types = {
        "comment",
        "line_comment",
        "block_comment",
        "comment_block",
        "single_line_comment",
        "multi_line_comment",
    },
    prefer_highlight = true,
    mode = "collapse",
    placeholder = "comment {count} lines", -- TODO: Find an icon for "comment"
    swallow_empty_lines_before = false,
    swallow_empty_lines_after = true,
    concealcursor = nil,
    gutter = {
        enabled = "collapse",
        icon = "∙", -- TODO: Find a better icon
        icon_above = "⎺", -- U+23BA horizontal scan line-1
        icon_below = "⎽", -- U+23BD horizontal scan line-9
        icon_between = " ̲̅",
        highlight = "Comment",
    },
}

---@type ConcealComments.Config
M.current = vim.deepcopy(M.defaults)

-- TODO: Should we be copying M.defaults or M.current?
-- If we call setup multiple times, do we want to amend the current configuration
-- or the default configuration. Have a look at how other plugins do it.

--- Set the configuration with the defaults applying where not specified.
---@param opts? ConcealComments.Config
function M.setup(opts)
    M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

--- Update the current configuration.
---@param opts? ConcealComments.Config
function M.update(opts)
    M.current = vim.tbl_deep_extend("force", M.current, opts or {})
end

return M
