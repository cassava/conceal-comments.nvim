local config = require("conceal-comments.config")
local core = require("conceal-comments.core")

local M = {}

--- Setup the plugin with user options
--- @param opts? ConcealComments.Config
function M.setup(opts)
    config.setup(opts)

    -- Define sign highlight if not already defined
    local gutter = config.current.gutter
    if gutter.enabled then
        vim.fn.sign_define("ConcealCommentsIndicator", { text = gutter.icon, texthl = gutter.hl })
    end

    -- Register user command
    vim.api.nvim_create_user_command("ConcealComments", function(cmd_opts)
        local subcmd = cmd_opts.fargs[1]
        local bufnr = vim.api.nvim_get_current_buf()

        if subcmd == "hide" then
            M.hide(bufnr)
        elseif subcmd == "show" then
            M.show(bufnr)
        elseif subcmd == "toggle" then
            M.toggle(bufnr)
        elseif subcmd == "mode" then
            local mode = cmd_opts.fargs[2] or nil
            M.switch_mode(bufnr, mode)
        else
            vim.notify(
                "ConcealComments: unknown subcommand '" .. subcmd .. "'. Use toggle, show, hide, or mode.",
                vim.log.levels.ERROR
            )
        end
    end, {
        -- TODO: Is nargs option needed here? Docs don't reference it...
        complete = function()
            -- TODO: How to properly complete for "mode"
            return { "toggle", "show", "hide", "mode" }
        end,
        desc = "Conceal or reveal comments in the current buffer",
    })
end

--- Print or change the conceal mode.
--- @param bufnr? integer
--- @param kind? "placeholder"|"collapse"|"toggle"
function M.mode(bufnr, kind)
    -- Print conceal mode
    if not kind then
        vim.notify("ConcealComments mode is: '" .. config.current.mode .. "'")
        return
    end

    -- Set conceal mode
    if kind == "placeholder" or kind == "collapse" then
        config.current.mode = kind
    elseif kind == "toggle" then
        if config.current.mode == "placeholder" then
            config.current.mode = "collapse"
        else
            config.current.mode = "placeholder"
        end
    else
        vim.notify(
            "ConcealComments: unknown mode '" .. kind .. "'. Use toggle, placeholder, or collapse.",
            vim.log.levels.ERROR
        )
        return
    end

    -- Re-apply concealment if hidden
    if vim.b[bufnr].conceal_comments_active then
        M.hide(bufnr)
    end
end

--- Hide comments in the given buffer.
--- @param bufnr? integer
function M.hide(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    -- If already active, reveal first to avoid stacking
    if vim.b[bufnr].conceal_comments_active then
        core.reveal(bufnr)
    end
    -- Ensure tree-sitter is parsed before detecting
    pcall(vim.treesitter.get_parser, bufnr)
    core.conceal(bufnr)
end

--- Show comments in the given buffer.
--- @param bufnr? integer
function M.show(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if not vim.b[bufnr].conceal_comments_active then
        return
    end
    core.reveal(bufnr)
end

--- Toggle comment visibility in the given buffer.
--- @param bufnr? integer
function M.toggle(bufnr)
    -- NOTE: The problem with using bufnr is that the
    -- use of virtual text etc is window specific.
    -- Look into this!!

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    if vim.b[bufnr].conceal_comments_active then
        M.show(bufnr)
    else
        M.hide(bufnr)
    end
end

return M
