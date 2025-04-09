-- plugin/code_regions.lua
-- This file ensures the plugin is loaded.
-- The actual setup should be done by the user calling require('code-regions').setup()

-- No code needed here typically, unless you want to force some setup
-- or provide default commands even if the user doesn't call setup().
-- However, the standard practice is to let the user call setup().

-- You could add a check here to see if setup was called and provide a warning if not,
-- but it's often better to just let it fail gracefully if core modules aren't configured.

-- Example (optional): Add a command that works even without setup
-- vim.api.nvim_create_user_command("CodeRegionsInfo", function()
--   print("code-regions.nvim: Call require('code-regions').setup() to configure.")
-- end, { desc = "Show code-regions.nvim setup info" })

