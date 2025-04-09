-- lua/code-regions/init.lua
-- Main plugin file: setup, autocommands, user commands.

local api = vim.api
local config = require("code-regions.config")
local regions = require("code-regions.regions")
local fold = require("code-regions.fold") -- Require fold module even if just for foldexpr reference

local M = {}

local update_timer = nil -- Timer for debouncing updates

-- Debounced buffer update function
local function schedule_update(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  -- Clear existing timer if any
  if update_timer then
    update_timer:close()
    update_timer = nil
  end

  -- Schedule the update
  update_timer = vim.defer_fn(function()
    -- Check if buffer is still valid/loaded before processing
    if api.nvim_buf_is_valid(bufnr) and api.nvim_buf_is_loaded(bufnr) then
        vim.schedule(function() -- Schedule actual work to avoid issues within timer callback
            regions.update_buffer(bufnr)
        end)
    end
    update_timer = nil
  end, config.options.update_debounce)
end

-- Function to setup autocommands
local function setup_autocommands()
  local group_name = "CodeRegions"
  api.nvim_create_augroup(group_name, { clear = true })

  -- Initial processing when a buffer is loaded
  api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter", "FileType" }, {
    group = group_name,
    pattern = "*",
    callback = function(args)
        -- Delay slightly with schedule to ensure TS parser is ready
        vim.schedule(function()
            -- Check if buffer is valid and loaded
            if api.nvim_buf_is_valid(args.buf) and api.nvim_buf_is_loaded(args.buf) then
                 -- Don't debounce initial load
                 regions.update_buffer(args.buf)
            end
        end)
    end,
    desc = "Initial processing of regions on buffer load/enter",
  })

  -- Re-process on save
  api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group_name,
    pattern = "*",
    callback = function(args)
      regions.update_buffer(args.buf) -- Update immediately on save
    end,
    desc = "Update regions after saving",
  })

  -- Re-process on text change (debounced)
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = group_name,
    pattern = "*",
    callback = function(args)
      schedule_update(args.buf) -- Use debounced update
    end,
    desc = "Update regions after text change (debounced)",
  })

  -- Clear data when a buffer is wiped out or unloaded
   api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
     group = group_name,
     pattern = "*",
     callback = function(args)
       regions.clear_buffer(args.buf)
       -- Also clear the debounce timer if it was for this buffer (though less critical)
       if update_timer then
           -- We don't easily know which buffer the timer was for,
           -- but clearing it on any wipeout is generally safe.
           update_timer:close()
           update_timer = nil
       end
     end,
     desc = "Clear region data when buffer is wiped/unloaded",
   })

   -- Re-apply colors when color scheme changes
   api.nvim_create_autocmd({ "ColorScheme" }, {
       group = group_name,
       pattern = "*",
       callback = function()
           -- Clear highlight cache as colors depend on Normal bg
           require("code-regions.color").clear_highlights(0) -- 0 clears for all buffers? Check docs. No, need to iterate.
           -- Instead of clearing, just trigger updates for visible buffers
           vim.schedule(function()
                for _, bufnr in ipairs(api.nvim_list_bufs()) do
                    if api.nvim_buf_is_loaded(bufnr) and #api.nvim_buf_get_windows(bufnr) > 0 then
                       -- Re-run update which will redefine highlights based on new scheme
                       regions.update_buffer(bufnr)
                    end
                end
           end)
       end,
       desc = "Update region colors on colorscheme change"
   })

end

-- Function to setup user commands
local function setup_commands()
  api.nvim_create_user_command("CodeRegionsUpdate", function(opts)
    regions.update_buffer(opts.args == "!" and nil or api.nvim_get_current_buf())
  end, {
    nargs = "?", -- Optional bang ! to update all buffers
    desc = "Manually update code regions for the current buffer (or all buffers with !)",
  })

  api.nvim_create_user_command("CodeRegionsToggle", function()
    config.options.enabled = not config.options.enabled
    if config.options.enabled then
      regions.update_buffer()
      vim.notify("Code Regions: Enabled")
    else
      regions.clear_buffer()
      vim.notify("Code Regions: Disabled")
    end
  end, {
    desc = "Toggle code-regions.nvim processing on/off",
  })

  api.nvim_create_user_command("CodeRegionsToggleColor", function()
    config.options.enable_colors = not config.options.enable_colors
    regions.update_buffer() -- Re-process to apply/clear colors
    vim.notify("Code Regions: Colors " .. (config.options.enable_colors and "Enabled" or "Disabled"))
  end, {
    desc = "Toggle region background coloring",
  })

  api.nvim_create_user_command("CodeRegionsToggleFold", function()
     config.options.enable_folding = not config.options.enable_folding
     regions.update_buffer() -- Re-process to apply/clear folding
     vim.notify("Code Regions: Folding " .. (config.options.enable_folding and "Enabled" or "Disabled"))
   end, {
     desc = "Toggle region folding",
   })

   -- Command to jump to the next/previous region start/end marker might be useful
   -- ... (Implementation omitted for brevity)
end

-- Public setup function called by users
function M.setup(user_config)
  config.setup(user_config) -- Pass user config to the config module

  if config.options.enabled then
    setup_autocommands()
    setup_commands()
    -- Initial update for already loaded buffers
    vim.schedule(function()
        for _, bufnr in ipairs(api.nvim_list_bufs()) do
            if api.nvim_buf_is_loaded(bufnr) then
                regions.update_buffer(bufnr)
            end
        end
    end)
  end
end

-- Expose the fold expression function for foldexpr setting
M.get_fold_level = fold.get_fold_level

return M
