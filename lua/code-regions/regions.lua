-- lua/code-regions/regions.lua
-- Manages region data, performs buffer scanning, and stores region info.
-- Updated: Ensure fold options are set correctly and trigger fold updates.
-- Updated: Temporarily comment out default fold closing for debugging fold levels.

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
  local winid = api.nvim_get_current_win() -- Get current window ID

  -- Check if buffer is valid and loaded before proceeding
  if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
      -- vim.notify("Code Regions: Skipping update for invalid/unloaded buffer " .. bufnr, vim.log.levels.DEBUG)
      return
  end

  -- Check if plugin is enabled and filetype is allowed
   local lang = vim.bo[bufnr].filetype
   if not config.options.enabled
      or not lang
      or vim.tbl_contains(config.options.disabled_filetypes, lang) then
     M.clear_buffer(bufnr) -- Clear any existing data/visuals if disabled
     -- vim.notify("Code Regions: Plugin disabled or filetype '" .. tostring(lang) .. "' blocked.", vim.log.levels.DEBUG)
     return
   end

  -- vim.notify("Code Regions: Updating buffer " .. bufnr, vim.log.levels.DEBUG)

  -- 1. Find all markers
  local markers = parser.find_markers(bufnr)

  -- 2. Build region tree
  local region_data = build_region_tree(markers)

  -- 3. Store data in buffer variable
  vim.b[bufnr][buffer_data_key] = region_data
  -- vim.print("Updated region data:", vim.inspect(region_data))

  -- 4. Clear previous visuals
  color.clear_highlights(bufnr)
  -- Folding is handled by foldexpr, but we need to trigger an update

  -- 5. Apply new visuals (coloring)
  if config.options.enable_colors then
    for _, region in ipairs(region_data.regions) do
      -- Apply highlight from line *after* start marker to line *before* end marker
      color.apply_highlight(bufnr, region.start_lnum, region.end_lnum, region.level)
    end
  end

  -- 6. Handle folding
  if config.options.enable_folding then
      -- *** CHANGE: Ensure fold settings are applied correctly ***
      -- Set buffer-local foldexpr
      vim.bo[bufnr].foldexpr = 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)'
      -- Set window-local foldmethod (for the current window viewing this buffer)
      -- Need to handle multiple windows potentially viewing the same buffer
      local target_wins = api.nvim_buf_get_windows(bufnr)
      for _, current_winid in ipairs(target_wins) do
          -- Check if window is valid before setting options
          if api.nvim_win_is_valid(current_winid) then
              vim.wo[current_winid].foldmethod = 'expr'
              vim.wo[current_winid].foldenable = true -- Ensure folding is enabled in the window
          end
      end

      -- *** CHANGE: Trigger fold update using 'noautocmd normal! zX' ***
      -- This forces Vim to re-evaluate folds based on the new foldexpr
      -- Execute in the context of the relevant window(s)
      for _, current_winid in ipairs(target_wins) do
          if api.nvim_win_is_valid(current_winid) then
              -- Use win_execute to run command in specific window context
              pcall(vim.fn.win_execute, current_winid, 'noautocmd normal! zX')
          end
      end

      -- *** TODO: Re-enable default fold closing after confirming levels work ***
      -- Apply default folding state AFTER processing all regions and updating folds
      -- local should_fold_all = config.options.fold_by_default
      -- for _, region in ipairs(region_data.regions) do
      --     if region.fold or should_fold_all then
      --         for _, current_winid in ipairs(target_wins) do
      --             if api.nvim_win_is_valid(current_winid) then
      --                 -- Check if foldmethod is still expr before trying to close
      --                 if vim.wo[current_winid].foldmethod == 'expr' then
      --                      -- vim.print("Closing fold at line", region.start_lnum, "in window", current_winid)
      --                      pcall(vim.fn.win_execute, current_winid, region.start_lnum .. 'foldclose')
      --                 end
      --             end
      --         end
      --     end
      -- end
      -- Force update folds view again after potentially closing some
      -- for _, current_winid in ipairs(target_wins) do
      --     if api.nvim_win_is_valid(current_winid) then
      --          pcall(vim.fn.win_execute, current_winid, 'noautocmd normal! zX')
      --     end
      -- end


  else
      -- If folding is disabled, reset fold method for relevant windows
      local target_wins = api.nvim_buf_get_windows(bufnr)
      for _, current_winid in ipairs(target_wins) do
          if api.nvim_win_is_valid(current_winid) then
              -- Only reset if *this plugin* set it
              if vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
                 vim.wo[current_winid].foldmethod = 'manual' -- Or sync with global setting? Manual is safe.
                 vim.bo[bufnr].foldexpr = '' -- Clear buffer foldexpr too
                 pcall(vim.fn.win_execute, current_winid, 'noautocmd normal! zX') -- Update folds view
              end
          end
      end
       -- Ensure buffer foldexpr is cleared if it was ours
      if vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
          vim.bo[bufnr].foldexpr = ''
      end
  end

  -- Optional: Add diagnostics for errors in region_data.errors
  -- ...
end

-- Clear all data and visuals for a buffer
function M.clear_buffer(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if not api.nvim_buf_is_valid(bufnr) then return end

    vim.b[bufnr][buffer_data_key] = nil
    color.clear_highlights(bufnr)

    -- Reset folding if it was set by this plugin
    local reset_fold = false
    if vim.bo[bufnr].foldexpr == 'v:lua.require("code-regions.fold").get_fold_level(v:lnum)' then
        vim.bo[bufnr].foldexpr = ''
        reset_fold = true
    end

    if reset_fold then
        local target_wins = api.nvim_buf_get_windows(bufnr)
        for _, current_winid in ipairs(target_wins) do
            if api.nvim_win_is_valid(current_winid) then
                if vim.wo[current_winid].foldmethod == 'expr' then
                    vim.wo[current_winid].foldmethod = 'manual' -- Reset to a default
                    pcall(vim.fn.win_execute, current_winid, 'noautocmd normal! zX') -- Update folds view
                end
            end
        end
    end
end

-- Get the processed region data for a buffer
function M.get_buffer_data(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(bufnr) then return nil end
  return vim.b[bufnr][buffer_data_key]
end


return M
