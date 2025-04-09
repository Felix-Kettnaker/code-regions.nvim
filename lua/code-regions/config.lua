-- lua/code-regions/config.lua
-- Handles plugin configuration and default values.

local M = {}

-- Default configuration values
M.defaults = {
  -- Enable the plugin
  enabled = true,
  -- Enable background coloring
  enable_colors = true,
  -- Enable folding
  enable_folding = true,
  -- Initialize all regions as folded
  fold_by_default = false,
  -- List of background colors to cycle through (hex format).
  -- If empty or nil, colors will be generated automatically.
  colors = {},
  -- Configuration for automatic color generation
  color_generation = {
    -- How much to shift the lightness (L in HSL) for each nesting level.
    -- Can be positive or negative.
    lightness_step = -0.05, -- Make nested regions slightly darker by default
    -- Minimum and maximum lightness values (0 to 1)
    min_lightness = 0.1,
    max_lightness = 0.9,
    -- Saturation value to use for generated colors (0 to 1).
    -- If nil, uses the saturation of the 'Normal' background.
    saturation = nil,
  },
  -- Keywords to recognize for starting and ending regions
  region_keywords = {
    start = { "#region", "region" }, -- Add more as needed, e.g., "BEGIN"
    end_ = { "#endregion", "endregion" }, -- Add more as needed, e.g., "END"
  },
  -- Whether keyword matching should be case sensitive
  case_sensitive = false,
  -- Filetypes to disable the plugin for
  disabled_filetypes = { "log", "help", "markdown", "text" },
  -- Debounce time in milliseconds for processing changes
  update_debounce = 300,
  -- Tree-sitter query to find comment nodes.
  -- This might need adjustments based on specific language parsers.
  comment_query = [[
    (comment) @comment
    (line_comment) @comment
    (block_comment) @comment
    ; Add language-specific comment nodes if needed
  ]],
}

-- Holds the current configuration (defaults merged with user options)
M.options = {}

-- Merges user configuration with defaults.
-- Creates a deep copy to avoid modifying the defaults table.
local function merge_config(user_config)
  local merged = vim.deepcopy(M.defaults)
  if user_config then
    for key, value in pairs(user_config) do
      if type(value) == "table" and type(merged[key]) == "table" then
        -- Recursively merge nested tables (like color_generation)
        merged[key] = vim.tbl_deep_extend("force", merged[key], value)
      else
        merged[key] = value
      end
    end
  end
  return merged
end

-- Setup function called by the user in their config.
-- Example: require('code-regions').setup({ enable_colors = false })
function M.setup(user_config)
  M.options = merge_config(user_config)

  -- Convert keywords to lowercase if not case sensitive for easier matching
  if not M.options.case_sensitive then
    local lower_keywords = { start = {}, end_ = {} }
    for _, keyword in ipairs(M.options.region_keywords.start) do
      table.insert(lower_keywords.start, keyword:lower())
    end
    for _, keyword in ipairs(M.options.region_keywords.end_) do
      table.insert(lower_keywords.end_, keyword:lower())
    end
    M.options.region_keywords = lower_keywords
  end

  -- Validate configuration if needed (e.g., check color formats)
  -- ...
end

-- Initialize with default options if setup is not called
M.setup()

return M
