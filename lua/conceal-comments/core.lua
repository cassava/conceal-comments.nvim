local config = require("conceal-comments.config").current

local M = {}

local ns_conceal = vim.api.nvim_create_namespace("conceal_comments_lines")
local ns_signs = vim.api.nvim_create_namespace("conceal_comments_signs")

-- TODO: Replace block type with vim.range once it's stable.
---@class ConcealComments.Block
---@field start_line integer 0-indexed inclusive
---@field end_line integer 0-indexed inclusive

--- Detect comment lines using tree-sitter.
---@param bufnr integer
---@return integer[]|nil List of 0-indexed line numbers, or nil if no parser is available.
local function detect_comments_ts(bufnr)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    if not ok or not parser then
        return nil
    end

    local comment_lines = {}
    local seen = {}

    -- According to the docs, this is necessary. What I wonder is if the nested
    -- iteration is necessary.
    parser:parse()
    parser:for_each_tree(function(tree, _)
        local root = tree:root()

        local function walk(node)
            local node_type = node:type()
            for _, ct in ipairs(config.node_types) do
                if node_type == ct then
                    local sr, _, er, ec = node:range()
                    -- If end_col is 0, the node ends at the start of end_row
                    -- (i.e. the newline of the previous row).
                    -- Don't include end_row in that case.
                    if ec == 0 and er > sr then
                        er = er - 1
                    end
                    for line = sr, er do
                        if not seen[line] then
                            seen[line] = true
                            table.insert(comment_lines, line)
                        end
                    end
                return
                end
            end
            for child in node:iter_children() do
                walk(child)
            end
        end

        walk(root)
    end)

    -- TODO: Is sorting necessary?
    table.sort(comment_lines)
    return comment_lines
end

--- Detect comment lines using highlight groups as fallback
---@param bufnr integer
---@return integer[]
local function detect_comments_hl(bufnr)
    local comment_lines = {}
    local line_count = vim.api.nvim_buf_line_count(bufnr)

    for lnum = 0, line_count - 1 do
        local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum+1, false)[1]
        if line and line:match("%S") then
            local col = line:find("%S") - 1
            local captures = vim.treesitter.get_captures_at_pos(bufnr, lnum, col)
            for _, cap in ipairs(captures) do
                if cap.capture:match("^comment") then
                    table.insert(comment_lines, lnum)
                    break
                end
            end
        end
    end

    return comment_lines
end

--- Get comment lines for a buffer.
---@param bufnr integer
---@return integer[]
function M.get_comment_lines(bufnr)
    if not config.prefer_highlight then
        local lines = detect_comments_ts(bufnr)
        if lines ~= nil then
            return lines
        end
    end
    return detect_comments_hl(bufnr)
end

--- Group adjacent comment lines into blocks, optionally swallowing empty lines
---@param bufnr integer
---@param comment_lines integer[]
---@return ConcealComments.Block[]
function M.group_into_blocks(bufnr, comment_lines)
    if #comment_lines == 0 then
        return {}
    end

    -- TODO: Use vim.range() once it's stable (can we modify an existing range though?)
    local blocks = {}
    local current_start = comment_lines[1]
    local current_end = comment_lines[1]
    local line = nil

    for i = 2, #comment_lines do
        line = comment_lines[i]
        if line == current_end + 1 then
            current_end = line
        else
            table.insert(blocks, { start_line = current_start, end_line = current_end })
            current_start = line
            current_end = line
        end
    end
    -- Don't double the last line
    if line ~= current_start then
        table.insert(blocks, { start_line = current_start, end_line = current_end })
    end

    if config.swallow_empty_lines_before or config.swallow_empty_lines_after then
        -- Swallow empty lines that are directly adjacent to comment blocks.
        -- This removes visual gaps left behind when comments are hidden.
        local line_count = vim.api.nvim_buf_line_count(bufnr)

        local merged = {}
        for _, block in ipairs(blocks) do
            if config.swallow_empty_lines_before then
                while block.start_line > 0 do
                    local prev_idx = block.start_line - 1
                    local prev = vim.api.nvim_buf_get_lines(bufnr, prev_idx, prev_idx + 1, false)[1]
                    if prev and prev:match("^%s*$") then
                        block.start_line = prev_idx
                    else
                        break
                    end
                end
            end
            if config.swallow_empty_lines_after then
                while block.end_line < line_count - 1 do
                    local next_idx = block.end_line + 1
                    local next_line = vim.api.nvim_buf_get_lines(bufnr, next_idx, next_idx + 1, false)[1]
                    if next_line and next_line:match("^%s*$") then
                        block.end_line = next_idx
                    else
                        break
                    end
                end
            end

            -- Check if updated block merges with previous block
            if #merged == 0 then
                table.insert(merged, block)
            else
                local prev_block = merged[#merged]
                if prev_block.end_line + 1 >= block.start_line then
                    -- They overlap so just update the previous block instead of adding a new block
                    -- TODO: Is math.max really needed? Probably not...
                    assert(block.end_line >= prev_block.end_line, "math.max is needed after all")
                    prev_block.end_line = math.max(block.end_line, prev_block.end_line)
                else
                    table.insert(merged, block)
                end
            end
        end

        blocks = merged
    end

    return blocks
end

--- Apply collapse concealment using conceal_lines extmarks.
---@param bufnr integer
---@param blocks ConcealComments.Block[]
local function conceal_collapse(bufnr, blocks)
    -- Set conceallevel in all windows showing this buffer
    M.set_conceallevel(bufnr)

    -- Place conceal_lines extmarks for each block.
    -- The range must stay within the last comment line (end_row inclusive),
    -- so we use end_col at the end of the last line rather than (next_row, 0).
    local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    for _, block in ipairs(blocks) do
        local last_line = buf_lines[block.end_line + 1] or ""
        vim.api.nvim_buf_set_extmark(bufnr, ns_conceal, block.start_line, 0, {
            end_row = block.end_line,
            end_col = #last_line,
            conceal_lines = "",
        })
    end

    -- FIXME: This is pointless when concealling all lines, since the line
    -- where the gutter signs are placed are not even visible!
    --
    -- Perhaps we should place the signs one above each hidden comment.
    -- However, this is more likely to conflict with other signs placed in the gutter.
    --
    -- TODO: Add a healthcheck where we check for this.
    --
    -- Place gutter signs on the first line of each block
    if config.gutter.enabled == "collapse" or config.gutter.enabled == "always" then
        M.place_signs_collapse(bufnr, blocks)
    end
end

--- Reveal from collapse mode
---@param bufnr integer
local function reveal_collapse(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_conceal, 0, -1)
    M.clear_signs(bufnr)
    M.restore_conceallevel(bufnr)
end

local function conceal_placeholder(bufnr)
    -- TODO: Finish implementation
end

local function reveal_placeholder(bufnr)
    -- TODO: Finish implementation
end

--- Place signs in the gutter.
---@param bufnr integer
---@param blocks ConcealComments.Block[]
function M.place_signs_collapse(bufnr, blocks)
    -- There is an edge case that we are not handling here:
    -- When the very first comment follows a non-comment and then a comment:
    --
    --     // comment on line 0
    --     statement
    --     // another comment
    --
    -- Then the sign should be placed where statement is for both above and
    -- below. In the implementation here we'll overwrite the first setting.
    -- This is going to happen so rarely it's not really worth the effort for now.
    local cfg = config.gutter
    local pos, icon
    for _, block in ipairs(blocks) do
        if block.start_line == 0 then
            pos = block.end_line + 1
            icon = cfg.icon_above
        else
            pos = block.start_line - 1
            icon = cfg.icon_below
        end
        vim.api.nvim_buf_set_extmark(bufnr, ns_signs, pos, 0, {
            sign_text = icon,
            sign_hl_group = cfg.highlight,
        })
    end
end

--- Clear signs in the gutter.
---@param bufnr integer
function M.clear_signs(bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, ns_signs, 0, -1)
end

--- Set conceallevel on all windows displaying the buffer.
--- conceal_lines requires conceallevel >= 2 to hide lines.
--- Optionally, sets concealcursor if configured.
---@param bufnr integer
function M.set_conceallevel(bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        local prev = vim.wo[win].conceallevel
        if not vim.w[win].conceal_comments_prev_conceallevel then
            vim.w[win].conceal_comments_prev_conceallevel = prev
        end
        if prev < 2 then
            vim.wo[win].conceallevel = 2
        end

        -- Only set concealcursor if user explicitely configured it
        if config.concealcursor then
            local prev_cc = vim.wo[win].concealcursor
            if not vim.w[win].conceal_comments_prev_concealcursor then
                vim.w[win].conceal_comments_prev_concealcursor = prev_cc
            end
            vim.wo[win].concealcursor = config.concealcursor
        end
    end
end

--- Restore conceallevel (and concealcursor if set) on all windows
---@param bufnr integer
function M.restore_conceallevel(bufnr)
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
        local prev = vim.w[win].conceal_comments_prev_conceallevel
        if prev ~= nil then
            vim.wo[win].conceallevel = prev
            vim.w[win].conceal_comments_prev_conceallevel = nil
        end
        local prev_cc = vim.w[win].conceal_comments_prev_conceallevel
        if prev_cc ~= nil then
            vim.wo[win].concealcursor = prev_cc
            vim.w[win].conceal_comments_prev_concealcursor = nil
        end
    end
end

function M.conceal(bufnr)
    local comment_lines = M.get_comment_lines(bufnr)
    local blocks = M.group_into_blocks(bufnr, comment_lines)

    if #blocks == 0 then
        return
    end

    if config.mode == "collapse" then
        conceal_collapse(bufnr, blocks)
    else
        conceal_placeholder(bufnr, blocks)
    end

    vim.b[bufnr].conceal_comments_active = true
    vim.b[bufnr].conceal_comments_mode = config.mode
end

function M.reveal(bufnr)
    local mode = vim.b[bufnr].conceal_comments_mode or config.mode
    if mode == "collapse" then
        reveal_collapse(bufnr)
    else
        reveal_placeholder(bufnr)
    end

    vim.b[bufnr].conceal_comments_active = false
    vim.b[bufnr].conceal_comments_mode = nil
end

return M
