-- lua/code-regions/fold.lua
-- Provides the foldexpr function for Neovim's folding.

local regions = require("code-regions.regions")
local config = require("code-regions.config")

local M = {}

-- foldexpr function to be called by Neovim
-- Determines the fold level for a given line number (lnum, 1-indexed)
function M.get_fold_level(lnum)
  if not config.options.enabled or not config.options.enable_folding then
    return "=" -- Return '=' tells Neovim the level is unchanged
  end

  local buf_data = regions.get_buffer_data() -- Gets data for current buffer
  if not buf_data or not buf_data.regions then
    return "="
  end

  local max_level_at_lnum = 0
  local is_start_line = false
  local is_end_line = false

  for _, region in ipairs(buf_data.regions) do
    -- Check if the line is the start marker line
    if lnum == region.start_lnum then
      is_start_line = true
      max_level_at_lnum = math.max(max_level_at_lnum, region.level)
      -- vim.print(string.format("Line %d is START of region level %d", lnum, region.level))
    -- Check if the line is the end marker line
    elseif lnum == region.end_lnum then
      is_end_line = true
      -- The level *inside* the fold ending here is region.level
      -- The level *at* the end line itself should be one less, or the level of the containing region
      -- Let's determine the level *containing* this end line.
      local containing_level = 0
      for _, r in ipairs(buf_data.regions) do
          if r.start_lnum < lnum and r.end_lnum > lnum then
              containing_level = math.max(containing_level, r.level)
          end
      end
       max_level_at_lnum = math.max(max_level_at_lnum, containing_level)
      -- vim.print(string.format("Line %d is END of region level %d, containing level %d", lnum, region.level, containing_level))

    -- Check if the line is inside a region (but not the start/end marker lines)
    elseif lnum > region.start_lnum and lnum < region.end_lnum then
      max_level_at_lnum = math.max(max_level_at_lnum, region.level)
      -- vim.print(string.format("Line %d is INSIDE region level %d", lnum, region.level))
    end
  end

  -- Determine foldexpr return value based on findings
  if is_start_line then
    -- Mark the start of a fold at the highest level starting here
    -- vim.print(string.format("Line %d -> '> %d'", lnum, max_level_at_lnum))
    return ">" .. max_level_at_lnum
  elseif is_end_line then
     -- Mark the end of a fold. The level should correspond to the fold *ending* here.
     -- We need the level of the *innermost* fold that ends exactly on this line.
     local ending_level = 0
     for _, region in ipairs(buf_data.regions) do
         if region.end_lnum == lnum then
             ending_level = math.max(ending_level, region.level)
         end
     end
     if ending_level > 0 then
       -- vim.print(string.format("Line %d -> '< %d'", lnum, ending_level))
       -- Returning the level seems to work better for ends than '<N'
       return tostring(ending_level) -- Or maybe max_level_at_lnum ? Test this. Let's try max_level_at_lnum
       -- return tostring(max_level_at_lnum)
     else
       -- If no fold ends here, return the level of the containing region
       -- vim.print(string.format("Line %d (end but no match) -> '= %d'", lnum, max_level_at_lnum))
       return tostring(max_level_at_lnum) -- Or "="? Let's stick to level.
     end
  elseif max_level_at_lnum > 0 then
    -- Line is inside a fold, return its level
    -- vim.print(string.format("Line %d -> '= %d'", lnum, max_level_at_lnum))
    return tostring(max_level_at_lnum)
  else
    -- Line is outside any fold
    -- vim.print(string.format("Line %d -> '= 0'", lnum))
    return "0" -- Level 0
  end
end

return M
