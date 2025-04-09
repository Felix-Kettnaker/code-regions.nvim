-- lua/code-regions/parser.lua
-- Uses Tree-sitter to find comments and parses region markers within them.

local ts_utils = require("nvim-treesitter.ts_utils")
local ts_query = require("nvim-treesitter.query")
local config = require("code-regions.config")

local M = {}

-- Cache for compiled Tree-sitter queries
local query_cache = {}

-- Get or compile the Tree-sitter query for comments
local function get_comment_query(lang)
  if query_cache[lang] then
    return query_cache[lang]
  end

  local parser = ts_query.get_parser(0, lang) -- Get parser for current buffer's lang
  if not parser then
    -- vim.notify("Code Regions: No Tree-sitter parser found for language: " .. lang, vim.log.levels.WARN)
    return nil
  end

  local query_str = config.options.comment_query
  local ok, query = pcall(ts_query.parse, lang, query_str)
  if not ok or not query then
    vim.notify("Code Regions: Failed to parse comment query for language: " .. lang .. "\n" .. tostring(query), vim.log.levels.ERROR)
    return nil
  end

  query_cache[lang] = query
  return query
end

-- Check if a keyword exists in the configured list
local function is_keyword(word, keyword_list)
    local check_word = config.options.case_sensitive and word or word:lower()
    for _, kw in ipairs(keyword_list) do
        if check_word == kw then
            return true
        end
    end
    return false
end

-- Parse a line of text to find a region marker
-- Returns: region_type ("start" or "end"), region_name (string or nil), fold_default (boolean)
function M.parse_marker(line_text)
  -- Trim leading/trailing whitespace from the line
  line_text = vim.trim(line_text)

  -- Basic check if line is potentially a comment (heuristic, TS is better)
  -- This function is called *after* TS identifies a comment node's text
  -- We need to find the region marker *within* the comment text

  local fold_default = line_text:sub(-1) == "-"

  -- Iterate through potential comment prefixes (crude, but needed if TS gives whole line)
  -- TODO: Improve this by getting the *actual* comment prefix from TS node if possible
  local potential_prefixes = { "--", "//", "#", ";", "/*", "*", "%%" }
  local comment_content = line_text

  for _, prefix in ipairs(potential_prefixes) do
      if line_text:startswith(prefix) then
          comment_content = vim.trim(line_text:sub(#prefix + 1))
          -- Handle block comment enders like */
          if comment_content:endswith("*/") then
              comment_content = vim.trim(comment_content:sub(1, -3))
          end
          break -- Assume first matching prefix is the one
      end
  end

  -- Now check for region keywords at the start of the comment content
  local region_type = nil
  local region_name = nil
  local keyword_found = nil

  for _, keyword in ipairs(config.options.region_keywords.start) do
      local compare_kw = config.options.case_sensitive and keyword or keyword:lower()
      local compare_content_start = config.options.case_sensitive and comment_content or comment_content:lower()

      if compare_content_start:startswith(compare_kw) then
          local rest = vim.trim(comment_content:sub(#keyword + 1))
          -- Handle the optional "-" for default folding right after the keyword
          local name_part = rest
          if rest:startswith("-") then
              fold_default = true
              name_part = vim.trim(rest:sub(2)) -- Name starts after the "-"
          end

          region_type = "start"
          region_name = #name_part > 0 and name_part or nil
          keyword_found = keyword -- Store the actual keyword found
          break
      end
  end

  if not region_type then
      for _, keyword in ipairs(config.options.region_keywords.end_) do
          local compare_kw = config.options.case_sensitive and keyword or keyword:lower()
          local compare_content_start = config.options.case_sensitive and comment_content or comment_content:lower()

          if compare_content_start:startswith(compare_kw) then
              local rest = vim.trim(comment_content:sub(#keyword + 1))
              region_type = "end"
              region_name = #rest > 0 and rest or nil
              keyword_found = keyword -- Store the actual keyword found
              break
          end
      end
  end

  -- Final check: ensure the keyword was at the very beginning of the comment content
  if region_type then
      local prefix_len = 0
      if keyword_found then
        prefix_len = #keyword_found
        -- Account for the optional "-" after start keywords
        if region_type == "start" and comment_content:sub(#keyword_found + 1, #keyword_found + 1) == "-" then
            prefix_len = prefix_len + 1
        end
      end

      -- Check if the character immediately following the keyword (and optional '-') is whitespace or end of string
      local char_after = comment_content:sub(prefix_len + 1, prefix_len + 1)
      if char_after == "" or char_after:match("%s") then
          -- It's a valid marker
          return region_type, region_name, fold_default
      else
          -- Keyword found, but not at the start or followed by non-whitespace
          return nil -- Not a valid region marker
      end
  end


  return nil -- No valid marker found
end


-- Find all region markers in a buffer using Tree-sitter
-- Returns a list of tables: { lnum = number, type = "start"|"end", name = string|nil, fold = boolean }
function M.find_markers(bufnr)
  local markers = {}
  local lang = vim.bo[bufnr].filetype
  if not lang or vim.tbl_contains(config.options.disabled_filetypes, lang) then
    return markers -- Don't process disabled filetypes
  end

  local query = get_comment_query(lang)
  if not query then
    return markers -- No query available for this language
  end

  local root = ts_utils.get_root_for_buf(bufnr)
  if not root then
    return markers -- No syntax tree available
  end

  local buffer_lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Iterate through all comment nodes found by the query
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local capture_name = query.captures[id]
    if capture_name == "comment" then
      local start_row, _, end_row, _ = node:range()
      -- Process each line within the comment node (important for block comments)
      for lnum = start_row, end_row do
        -- Get the text of the specific line
        -- lnum is 0-indexed, buffer_lines is 1-indexed from Lua
        local line_text = buffer_lines[lnum + 1]
        if line_text then
          local region_type, region_name, fold_default = M.parse_marker(line_text)
          if region_type then
            table.insert(markers, {
              lnum = lnum + 1, -- Store as 1-indexed line number
              type = region_type,
              name = region_name,
              fold = fold_default,
            })
          end
        end
      end
    end
  end

  -- Sort markers by line number
  table.sort(markers, function(a, b) return a.lnum < b.lnum end)

  -- vim.print("Found markers:", vim.inspect(markers))
  return markers
end


return M
