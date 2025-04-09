-- lua/code-regions/regions.lua
-- Manages region data, performs buffer scanning, and stores region info.

local api = vim.api
local parser = require("code-regions.parser")
local color = require("code-regions.color")
local config = require("code-regions.config")

local M = {}

-- Buffer-local variable to store processed region data
-- Structure: b:code_regions_data = { regions = { { start_lnum, end_lnum, level, name, fold } }, errors = {} }
local buffer_data_key = "code_regions_data"

-- Process markers and build region hierarchy
-- Returns a table: { regions = list_of_regions, errors = list_of_errors }
-- region = { start_lnum, end_lnum, level, name, fold }
-- error = { lnum, message }
local function build_region_tree(markers)
  local regions = {}
  local errors = {}
  local region_stack = {} -- Stack to track open regions { lnum, name, fold }

  for _, marker in ipairs(markers) do
    if marker.type == "start" then
      -- Push new region onto the stack
      table.insert(region_stack, {
        lnum = marker.lnum,
        name = marker.name,
        fold = marker.fold,
      })
    elseif marker.type == "end" then
      if #region_stack == 0 then
        -- Error: Unmatched end region
        table.insert(errors, { lnum = marker.lnum, message = "Unmatched end region marker" })
      else
        -- Pop the matching start region
        local start_region = table.remove(region_stack)
        -- Optional: Check if names match if both are provided
        if start_region.name and marker.name and start_region.name ~= marker.name then
          table.insert(errors, {
            lnum = marker.lnum,
            message = string.format("Mismatched region names: expected '%s', got '%s'", start_region.name, marker.name),
          })
        end
        -- Add the completed region to our list
        table.insert(regions, {
          start_lnum = start_region.lnum,
          end_lnum = marker.lnum,
          level = #region_stack + 1, -- Level is based on stack depth *before* popping
          name = start_region.name,   -- Use the name from the start marker
          fold = start_region.fold,   -- Use the fold state from the start marker
        })
      end
    end
  end

  -- Check for unclosed regions remaining on the stack
  for _, open_region in ipairs(region_stack) do
    table.insert(errors, { lnum = open_region.lnum, message = "Unclosed region marker" })
  end

  -- Sort regions primarily by start line, then by end line descending (outer regions first)
  table.sort(regions, function(a, b)
    if a.start_lnum ~= b.start_lnum then
      return a.start_lnum < b.start_lnum
    else
      return a.end_lnum > b.end_lnum -- Larger range (outer) comes first if starts are same
    end
  end)

  return { regions = regions, errors = errors }
end

-- Scan the buffer, find markers, build regions, and apply visuals
function M.update_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  -- Check if plugin is enabled and filetype is allowed
   local lang = vim.bo[bufnr].filetype
   if not config.options.enabled
      or not lang
      or vim.tbl_contains(config.options.disabled_filetypes, lang) then
     M.clear_buffer(bufnr) -- Clear any existing data/visuals if disabled
     return
   end

  -- 1. Find all markers
  local markers = parser.find_markers(bufnr)

  -- 2. Build region tree
  local region_data = build_region_tree(markers)

  -- 3. Store data in buffer variable
  vim.b[bufnr][buffer_data_key] = region_data
  -- vim.print("Updated region data:", vim.inspect(region_data))

  -- 4. Clear previous visuals
  color.clear_highlights(bufnr)
  -- Folding is handled by foldexpr, but we might need to trigger an update
  -- Diagnostics for errors could be added here too

  -- 5. Apply new visuals (coloring)
  if config.options.enable_colors then
    for _, region in ipairs(region_data.regions) do
      -- Apply highlight from line *after* start marker to line *before* end marker
      color.apply_highlight(bufnr, region.start_lnum, region.end_lnum -1, region.level)
    end
  end

  -- 6. Handle folding
  if config.options.enable_folding then
      -- Ensure fold settings are correct
      vim.wo[vim.api.nvim_buf_get_winnr(bufnr)].foldmethod = 'expr'
      vim.bo[bufnr].foldexpr = 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)'
      vim.wo[vim.api.nvim_buf_get_winnr(bufnr)].foldenable = true
      -- vim.cmd('normal! zX') -- Update folds in the buffer

      -- Apply default folding state AFTER processing all regions
      local should_fold_all = config.options.fold_by_default
      for _, region in ipairs(region_data.regions) do
          -- Fold if the specific region has fold=true OR if fold_by_default is true
          if region.fold or should_fold_all then
              -- Ensure the fold command targets the correct window if multiple are open
              local current_win = api.nvim_get_current_win()
              local target_wins = api.nvim_buf_get_windows(bufnr)
              for _, winid in ipairs(target_wins) do
                  -- Only close fold in windows where folding is enabled for this plugin
                  if vim.wo[winid].foldmethod == 'expr' and vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
                      pcall(api.nvim_win_call, winid, function()
                          -- Need to switch context briefly if not the current window
                          -- api.nvim_set_current_win(winid) -- Avoid this if possible
                          -- Use win_execute instead
                          vim.fn.win_execute(winid, region.start_lnum .. 'foldclose')
                      end)
                  end
              end
              -- Restore context if changed (though win_execute avoids this)
              -- api.nvim_set_current_win(current_win)
          end
      end
      -- Force update folds view after potentially closing some
      vim.cmd('noautocmd normal! zX')
  else
      -- If folding is disabled, reset fold method
      local current_foldmethod = vim.bo[bufnr].foldmethod
      if current_foldmethod == 'expr' and vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
         vim.wo[vim.api.nvim_buf_get_winnr(bufnr)].foldmethod = 'manual' -- Or whatever the default is
         vim.bo[bufnr].foldexpr = ''
         vim.cmd('noautocmd normal! zX') -- Update folds view
      end
  end

  -- Optional: Add diagnostics for errors in region_data.errors
  -- ...
end

-- Clear all data and visuals for a buffer
function M.clear_buffer(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    vim.b[bufnr][buffer_data_key] = nil
    color.clear_highlights(bufnr)

    -- Reset folding if it was set by this plugin
    if vim.bo[bufnr].foldmethod == 'expr' and vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
        vim.wo[vim.api.nvim_buf_get_winnr(bufnr)].foldmethod = 'manual' -- Reset to a default
        vim.bo[bufnr].foldexpr = ''
        vim.cmd('noautocmd normal! zX') -- Update folds view
    end
end

-- Get the processed region data for a buffer
function M.get_buffer_data(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return vim.b[bufnr][buffer_data_key]
end


return M
