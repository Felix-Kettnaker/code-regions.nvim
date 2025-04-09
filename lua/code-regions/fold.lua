-- lua/code-regions/fold.lua
-- Provides the foldexpr function for Neovim's folding.
-- Updated: Simplified logic based on fold-expr documentation.

local regions = require("code-regions.regions")
local config = require("code-regions.config")

local M = {}

-- foldexpr function to be called by Neovim
-- Determines the fold level for a given line number (lnum, 1-indexed)
function M.get_fold_level(lnum)
  -- Check if folding is enabled first
  if not config.options.enabled or not config.options.enable_folding then
    return "=" -- Return '=' tells Neovim the level is unchanged
  end

  local buf_data = regions.get_buffer_data() -- Gets data for current buffer
  -- If no data, or processing disabled, return '='
  if not buf_data or not buf_data.regions then
    -- vim.print(string.format("Line %d: No region data, returning '='", lnum))
    return "="
  end

  local current_level = 0
  local is_start_of_fold = false
  local start_fold_level = 0

  -- Find the deepest region this line belongs to
  for _, region in ipairs(buf_data.regions) do
    if lnum > region.start_lnum and lnum <= region.end_lnum then
      -- Line is inside or is the end line of this region
      current_level = math.max(current_level, region.level)
    end
    -- Check if this line starts a region
    if lnum == region.start_lnum then
      is_start_of_fold = true
      start_fold_level = math.max(start_fold_level, region.level)
    end
  end

  -- Determine foldexpr return value
  if is_start_of_fold then
    -- Mark the start of a fold at the highest level starting here
    -- vim.print(string.format("Line %d: Start of fold, returning '> %d'", lnum, start_fold_level))
    return ">" .. start_fold_level
  elseif current_level > 0 then
    -- Line is inside a fold (or is the end line), return its level
    -- vim.print(string.format("Line %d: Inside fold, returning '%d'", lnum, current_level))
    return tostring(current_level)
  else
    -- Line is outside any fold
    -- vim.print(string.format("Line %d: Outside fold, returning '0'", lnum))
    return "0" -- Level 0
  end
end

return M
