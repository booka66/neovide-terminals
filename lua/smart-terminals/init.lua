local M = {}

local term_count = 0
local terminals = {}
local current_term = 1
local terminal_names = {}
local terminal_scroll_positions = {}

-- Tmux utility functions
local tmux = {}

function tmux.is_available()
  return vim.fn.executable("tmux") == 1
end

function tmux.session_exists(session_name)
  if not tmux.is_available() then return false end
  local result = vim.fn.system("tmux has-session -t " .. vim.fn.shellescape(session_name) .. " 2>/dev/null")
  return vim.v.shell_error == 0
end

function tmux.create_session(session_name, start_dir)
  if not tmux.is_available() then return false end
  local cmd = "tmux new-session -d -s " .. vim.fn.shellescape(session_name)
  if start_dir then
    cmd = cmd .. " -c " .. vim.fn.shellescape(start_dir)
  end
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

function tmux.kill_session(session_name)
  if not tmux.is_available() then return false end
  vim.fn.system("tmux kill-session -t " .. vim.fn.shellescape(session_name) .. " 2>/dev/null")
  return vim.v.shell_error == 0
end

function tmux.list_sessions()
  if not tmux.is_available() then return {} end
  local output = vim.fn.system("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if vim.v.shell_error ~= 0 then return {} end
  local sessions = {}
  for session in output:gmatch("[^\r\n]+") do
    table.insert(sessions, session)
  end
  return sessions
end

local function save_scroll_position(term)
  if term.window and vim.api.nvim_win_is_valid(term.window) then
    local cursor_pos = vim.api.nvim_win_get_cursor(term.window)
    local view = vim.api.nvim_win_call(term.window, function()
      return vim.fn.winsaveview()
    end)
    terminal_scroll_positions[term.count] = {
      cursor = cursor_pos,
      view = view,
    }
  end
end

local function restore_scroll_position(term)
  if term.window and vim.api.nvim_win_is_valid(term.window) and terminal_scroll_positions[term.count] then
    local saved_pos = terminal_scroll_positions[term.count]
    vim.api.nvim_win_call(term.window, function()
      vim.fn.winrestview(saved_pos.view)
    end)
    vim.defer_fn(function()
      if term.window and vim.api.nvim_win_is_valid(term.window) then
        vim.api.nvim_win_set_cursor(term.window, saved_pos.cursor)
      end
    end, 50)
  end
end

local function get_smart_dir()
  local current_file = vim.fn.expand("%:p")
  if current_file ~= "" then
    local dir = vim.fn.fnamemodify(current_file, ":h")
    if vim.fn.isdirectory(dir) == 1 then
      local git_root =
        vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
      if vim.v.shell_error == 0 then
        git_root = vim.fn.trim(git_root)
        if git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
          return git_root
        end
      end
      return dir
    end
  end
  local cwd = vim.fn.getcwd()
  if vim.fn.isdirectory(cwd) == 1 then
    return cwd
  end
  return vim.fn.expand("~")
end

local function find_terminal_by_name(name)
  for i, term in ipairs(terminals) do
    if terminal_names[term.count] == name then
      return i, term
    end
  end
  return nil, nil
end

local function create_title_window(term, terminal_name)
  if term.window and vim.api.nvim_win_is_valid(term.window) then
    vim.schedule(function()
      pcall(function()
        if not term.window or not vim.api.nvim_win_is_valid(term.window) then
          return
        end
        
        local title_text = "── " .. terminal_name .. " ──"
        local win_width = vim.api.nvim_win_get_width(term.window)
        local centered_title = string.rep(" ", math.max(0, math.floor((win_width - string.len(title_text)) / 2))) .. title_text

        local title_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(title_buf, 0, -1, false, { centered_title })
        
        local title_win = vim.api.nvim_open_win(title_buf, false, {
          relative = "win",
          win = term.window,
          width = win_width,
          height = 1,
          row = 0,
          col = 0,
          style = "minimal",
          border = "none",
          zindex = 1000,
        })
        
        vim.api.nvim_win_set_option(title_win, "winblend", 0)
        vim.api.nvim_win_set_option(title_win, "winhighlight", "Normal:Title")
        
        term.title_win = title_win
        term.title_buf = title_buf

        restore_scroll_position(term)
      end)
    end)
  end
end

local function cleanup_title_window(term)
  if term.title_win and vim.api.nvim_win_is_valid(term.title_win) then
    vim.api.nvim_win_close(term.title_win, true)
  end
  if term.title_buf and vim.api.nvim_buf_is_valid(term.title_buf) then
    vim.api.nvim_buf_delete(term.title_buf, { force = true })
  end
end

local function new_terminal(name, dir)
  term_count = term_count + 1
  local terminal_dir = dir or get_smart_dir()
  local terminal_name = name or ("Terminal " .. term_count)
  
  -- Create tmux session name with consistent naming
  local session_name
  if name then
    local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    session_name = "smart-terminals-" .. clean_name
  else
    session_name = "smart-terminals-term-" .. term_count
  end
  
  -- Check if we should use tmux or fall back to regular terminal
  local use_tmux = tmux.is_available()
  
  if use_tmux then
    -- Create or attach to tmux session
    if not tmux.session_exists(session_name) then
      if not tmux.create_session(session_name, terminal_dir) then
        use_tmux = false
        vim.notify("Failed to create tmux session, falling back to regular terminal", vim.log.levels.WARN)
      end
    end
  end
  
  local Terminal = require("toggleterm.terminal").Terminal
  local cmd = nil
  
  if use_tmux then
    cmd = "tmux attach-session -t " .. vim.fn.shellescape(session_name)
  end
  
  local new_term = Terminal:new({
    count = term_count,
    direction = "float",
    dir = use_tmux and nil or terminal_dir,
    cmd = cmd,
    float_opts = {
      border = "none",
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      row = 0,
      col = 0,
      winblend = 3,
    },
    on_open = function(term)
      vim.cmd("startinsert")
      vim.b.terminal_title = terminal_name
      create_title_window(term, terminal_name)
    end,
    on_close = function(term)
      save_scroll_position(term)
      cleanup_title_window(term)
    end,
  })
  
  -- Store session info
  new_term.tmux_session = use_tmux and session_name or nil
  new_term.use_tmux = use_tmux
  
  table.insert(terminals, new_term)
  terminal_names[term_count] = terminal_name
  current_term = #terminals
  new_term:toggle()
end

local function create_predefined_terminal(name)
  local idx, term = find_terminal_by_name(name)
  
  -- Check if tmux session exists even if we don't have a terminal object for it
  local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  local session_name = "smart-terminals-" .. clean_name
  local use_tmux = tmux.is_available()
  
  if term then
    -- Terminal object exists, toggle it
    current_term = idx
    if term:is_open() then
      save_scroll_position(term)
    end
    term:toggle()
    if term:is_open() then
      vim.cmd("startinsert")
      restore_scroll_position(term)
    end
  elseif use_tmux and tmux.session_exists(session_name) then
    -- Tmux session exists but no terminal object, create terminal that attaches to existing session
    new_terminal(name, get_smart_dir())
  else
    -- Create new terminal (and session if using tmux)
    new_terminal(name, get_smart_dir())
  end
end

M.create_git_terminal = function()
  create_predefined_terminal("Git")
end

M.create_dev_terminal = function()
  create_predefined_terminal("Dev Server")
end

M.create_test_terminal = function()
  create_predefined_terminal("Tests")
end

M.create_claude_terminal = function()
  local name = "Claude"
  local idx, term = find_terminal_by_name(name)
  local clean_name = name:lower():gsub("[%s%-]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  local session_name = "smart-terminals-" .. clean_name
  local use_tmux = tmux.is_available()
  local should_send_command = false
  
  if term then
    -- Terminal object exists, toggle it
    current_term = idx
    if term:is_open() then
      save_scroll_position(term)
    end
    term:toggle()
    if term:is_open() then
      vim.cmd("startinsert")
      restore_scroll_position(term)
    end
  elseif use_tmux and tmux.session_exists(session_name) then
    -- Tmux session exists but no terminal object, create terminal that attaches to existing session
    new_terminal(name, get_smart_dir())
  else
    -- Create new terminal (and session if using tmux)
    should_send_command = true
    new_terminal(name, get_smart_dir())
  end
  
  -- Send claude command only if we created a brand new terminal/session
  if should_send_command then
    vim.defer_fn(function()
      if #terminals > 0 and terminals[current_term] then
        if terminals[current_term].use_tmux then
          -- Send command to tmux session
          local cmd = "tmux send-keys -t " .. vim.fn.shellescape(session_name) .. " 'claude' Enter"
          vim.fn.system(cmd)
        else
          -- Send to regular terminal
          terminals[current_term]:send("claude")
        end
      end
    end, 100)
  end
end

local function run_in_terminal(cmd, name)
  local Terminal = require("toggleterm.terminal").Terminal
  local command_name = name or ("Running: " .. cmd)
  local runner = Terminal:new({
    cmd = cmd,
    direction = "float",
    float_opts = {
      border = "none",
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      row = 0,
      col = 0,
      winblend = 3,
    },
    close_on_exit = false,
    on_open = function(term)
      vim.cmd("startinsert")
      create_title_window(term, command_name)
    end,
  })
  runner:toggle()
end

M.run_project_command = function()
  local cwd = vim.fn.getcwd()

  if vim.fn.filereadable(cwd .. "/package.json") == 1 then
    vim.ui.select(
      { "npm run dev", "npm run build", "npm run test", "npm install", "Custom command" },
      { prompt = "Select npm command:" },
      function(choice)
        if choice == "Custom command" then
          vim.ui.input({ prompt = "Enter command: " }, function(input)
            if input then
              run_in_terminal(input, "Custom")
            end
          end)
        elseif choice then
          run_in_terminal(choice, "NPM")
        end
      end
    )
  elseif vim.fn.filereadable(cwd .. "/Cargo.toml") == 1 then
    vim.ui.select(
      { "cargo run", "cargo build", "cargo test", "cargo check", "Custom command" },
      { prompt = "Select cargo command:" },
      function(choice)
        if choice == "Custom command" then
          vim.ui.input({ prompt = "Enter command: " }, function(input)
            if input then
              run_in_terminal(input, "Custom")
            end
          end)
        elseif choice then
          run_in_terminal(choice, "Cargo")
        end
      end
    )
  else
    vim.ui.input({ prompt = "Enter command to run: " }, function(input)
      if input then
        run_in_terminal(input, "Project")
      end
    end)
  end
end

local function cycle_terminals()
  if #terminals == 0 then
    new_terminal()
    return
  end

  if terminals[current_term] and terminals[current_term]:is_open() then
    save_scroll_position(terminals[current_term])
    terminals[current_term]:close()
  end

  current_term = current_term % #terminals + 1

  terminals[current_term]:toggle()
  if terminals[current_term]:is_open() then
    vim.cmd("startinsert")
    restore_scroll_position(terminals[current_term])
  end
end

local function cycle_backwards()
  if #terminals == 0 then
    new_terminal()
    return
  end

  if terminals[current_term] and terminals[current_term]:is_open() then
    save_scroll_position(terminals[current_term])
    terminals[current_term]:close()
  end

  current_term = current_term - 1
  if current_term < 1 then
    current_term = #terminals
  end

  terminals[current_term]:toggle()
  if terminals[current_term]:is_open() then
    restore_scroll_position(terminals[current_term])
  end
end

M.toggle_current_terminal = function()
  if #terminals == 0 then
    new_terminal()
    return
  end

  local term = terminals[current_term]

  if term:is_open() then
    save_scroll_position(term)
  end

  term:toggle()

  if term:is_open() then
    vim.cmd("startinsert")
    restore_scroll_position(term)
  end
end

M.close_current_terminal = function()
  if #terminals == 0 then
    return
  end

  if terminals[current_term] then
    local old_count = terminals[current_term].count
    local session_name = terminals[current_term].tmux_session
    
    terminals[current_term]:close()

    -- Note: We keep tmux sessions running for persistence
    -- Users can manually kill sessions with :lua require('smart-terminals').kill_tmux_session('session-name')
    
    table.remove(terminals, current_term)
    if terminal_names[old_count] then
      terminal_names[old_count] = nil
    end
    if terminal_scroll_positions[old_count] then
      terminal_scroll_positions[old_count] = nil
    end

    if #terminals > 0 then
      if current_term > #terminals then
        current_term = #terminals
      end

      terminals[current_term]:toggle()
      if terminals[current_term]:is_open() then
        vim.cmd("startinsert")
        restore_scroll_position(terminals[current_term])
      end
    else
      current_term = 1
      term_count = 0
    end
  end
end

M.show_terminal_info = function()
  if #terminals == 0 then
    print("No terminals open")
    return
  end

  local info = "Terminals (" .. #terminals .. "):\n"
  for i, term in ipairs(terminals) do
    local name = terminal_names[term.count] or "Terminal " .. i
    local current_marker = (i == current_term) and " (current)" or ""
    local session_info = ""
    if term.use_tmux and term.tmux_session then
      session_info = " [tmux: " .. term.tmux_session .. "]"
    end
    info = info .. "  " .. i .. ": " .. name .. current_marker .. session_info .. "\n"
  end
  print(info)
end

M.send_line_to_terminal = function()
  if #terminals == 0 then
    new_terminal()
  end
  
  local line = vim.fn.getline(".")
  local term = terminals[current_term]
  
  if term.use_tmux and term.tmux_session then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(term.tmux_session) .. " " .. vim.fn.shellescape(line) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    term:send(line .. "\r")
  end
  
  if not term:is_open() then
    term:toggle()
    restore_scroll_position(term)
  end
end

M.send_selection_to_terminal = function()
  if #terminals == 0 then
    new_terminal()
  end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])

  if #lines == 1 then
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  end

  local text = table.concat(lines, "\n")
  local term = terminals[current_term]
  
  if term.use_tmux and term.tmux_session then
    -- Send to tmux session
    local cmd = "tmux send-keys -t " .. vim.fn.shellescape(term.tmux_session) .. " " .. vim.fn.shellescape(text) .. " Enter"
    vim.fn.system(cmd)
  else
    -- Send to regular terminal
    term:send(text .. "\r")
  end
  
  if not term:is_open() then
    term:toggle()
    restore_scroll_position(term)
  end
end

M.rename_terminal = function()
  if #terminals == 0 then
    print("No terminal to rename")
    return
  end

  vim.ui.input({
    prompt = "New terminal name: ",
    default = terminal_names[terminals[current_term].count] or "",
  }, function(input)
    if input then
      terminal_names[terminals[current_term].count] = input

      local term = terminals[current_term]
      if term and term.window and vim.api.nvim_win_is_valid(term.window) then
        vim.schedule(function()
          pcall(function()
            if not term.window or not vim.api.nvim_win_is_valid(term.window) then
              return
            end
            
            local title_text = "── " .. input .. " ──"
            local win_width = vim.api.nvim_win_get_width(term.window)
            local centered_title = string.rep(" ", math.max(0, math.floor((win_width - string.len(title_text)) / 2))) .. title_text

            if term.title_win and vim.api.nvim_win_is_valid(term.title_win) and term.title_buf and vim.api.nvim_buf_is_valid(term.title_buf) then
              vim.api.nvim_buf_set_lines(term.title_buf, 0, -1, false, { centered_title })
            end
          end)
        end)
      end

      print("Terminal renamed to: " .. input)
    end
  end)
end

M.kill_all_terminals = function()
  -- Kill all terminal instances
  for _, term in ipairs(terminals) do
    term:shutdown()
  end
  terminals = {}
  terminal_names = {}
  terminal_scroll_positions = {}
  current_term = 1
  term_count = 0
  
  -- Kill all smart-terminals tmux sessions
  if tmux.is_available() then
    local all_sessions = tmux.list_sessions()
    local killed_count = 0
    
    for _, session in ipairs(all_sessions) do
      if session:match("^smart%-terminals%-") then
        if tmux.kill_session(session) then
          killed_count = killed_count + 1
        end
      end
    end
    
    if killed_count > 0 then
      print("All terminals and " .. killed_count .. " tmux sessions killed")
    else
      print("All terminals killed (no tmux sessions found)")
    end
  else
    print("All terminals killed")
  end
end

-- Utility function to kill a specific tmux session
M.kill_tmux_session = function(session_name)
  if tmux.is_available() then
    local success = tmux.kill_session(session_name)
    if success then
      print("Killed tmux session: " .. session_name)
    else
      print("Failed to kill tmux session: " .. session_name)
    end
  else
    print("tmux not available")
  end
end

-- Utility function to list all smart-terminals tmux sessions
M.list_tmux_sessions = function()
  if not tmux.is_available() then
    print("tmux not available")
    return
  end
  
  local all_sessions = tmux.list_sessions()
  local smart_sessions = {}
  
  for _, session in ipairs(all_sessions) do
    if session:match("^smart%-terminals%-") then
      table.insert(smart_sessions, session)
    end
  end
  
  if #smart_sessions == 0 then
    print("No smart-terminals tmux sessions found")
  else
    print("Smart-terminals tmux sessions:")
    for _, session in ipairs(smart_sessions) do
      print("  " .. session)
    end
  end
end

-- Kill all smart-terminals tmux sessions
M.kill_all_tmux_sessions = function()
  if not tmux.is_available() then
    print("tmux not available")
    return
  end
  
  local all_sessions = tmux.list_sessions()
  local killed_count = 0
  
  for _, session in ipairs(all_sessions) do
    if session:match("^smart%-terminals%-") then
      if tmux.kill_session(session) then
        killed_count = killed_count + 1
      end
    end
  end
  
  if killed_count > 0 then
    print("Killed " .. killed_count .. " smart-terminals tmux sessions")
  else
    print("No smart-terminals tmux sessions to kill")
  end
end

M.pick_terminal = function()
  if #terminals == 0 then
    print("No terminals available")
    return
  end

  local choices = {}
  for i, _ in ipairs(terminals) do
    local name = terminal_names[terminals[i].count] or ("Terminal " .. i)
    local status = terminals[i]:is_open() and " (open)" or " (closed)"
    table.insert(choices, i .. ": " .. name .. status)
  end

  vim.ui.select(choices, {
    prompt = "Select terminal:",
  }, function(choice)
    if choice then
      local term_num = tonumber(string.match(choice, "^(%d+):"))
      if term_num then
        if terminals[current_term] and terminals[current_term]:is_open() then
          save_scroll_position(terminals[current_term])
        end

        current_term = term_num
        terminals[current_term]:toggle()
        if terminals[current_term]:is_open() then
          vim.cmd("startinsert")
          restore_scroll_position(terminals[current_term])
        end
      end
    end
  end)
end

M.new_terminal = new_terminal
M.cycle_terminals = cycle_terminals
M.cycle_backwards = cycle_backwards

M.setup = function(opts)
  opts = opts or {}
  
  if not pcall(require, "toggleterm") then
    vim.notify("smart-terminals requires toggleterm.nvim to be installed", vim.log.levels.ERROR)
    return
  end

  -- Prevent double setup
  if vim.g.smart_terminals_setup_called then
    return
  end
  vim.g.smart_terminals_setup_called = true

  -- Set up toggleterm with the proper configuration
  local toggleterm_opts = {
    size = 20,
    open_mapping = [[<c-\>]],
    hide_numbers = true,
    shade_terminals = true,
    shading_factor = 2,
    start_in_insert = true,
    insert_mappings = true,
    terminal_mappings = true,
    persist_size = true,
    persist_mode = true,
    direction = "float",
    close_on_exit = true,
    shell = vim.o.shell,
    auto_scroll = false,
    float_opts = {
      border = "none",
      row = 0,
      col = 0,
      width = function()
        return vim.o.columns
      end,
      height = function()
        return vim.o.lines
      end,
      winblend = 3,
      highlights = {
        border = "FloatBorder",
        background = "Normal",
      },
    },
  }
  
  -- Merge user options with defaults
  if opts.toggleterm then
    toggleterm_opts = vim.tbl_deep_extend("force", toggleterm_opts, opts.toggleterm)
  end
  
  require("toggleterm").setup(toggleterm_opts)

  local map = vim.keymap.set

  map({ "n", "i", "t" }, "<M-t>", function() new_terminal() end, { desc = "New terminal tab" })
  map({ "n", "i", "t" }, "<D-t>", function() new_terminal() end, { desc = "New terminal tab (Cmd)" })
  map({ "n", "i", "t" }, "<C-Tab>", cycle_terminals, { desc = "Cycle terminal tabs" })
  map({ "n", "i", "t" }, "<C-S-Tab>", cycle_backwards, { desc = "Cycle terminal tabs backwards" })
  map({ "n", "i", "t" }, "<C-\\>", M.toggle_current_terminal, { desc = "Toggle current terminal" })
  
  map("t", "<C-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })
  map("t", "<D-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })
  map("t", "<M-w>", M.close_current_terminal, { desc = "Close current terminal and switch to next" })
  
  map("t", "<C-h>", "<C-\\><C-N><C-w>h", { desc = "Terminal left window nav" })
  map("t", "<C-j>", "<C-\\><C-N><C-w>j", { desc = "Terminal down window nav" })
  map("t", "<C-k>", "<C-\\><C-N><C-w>k", { desc = "Terminal up window nav" })
  map("t", "<C-l>", "<C-\\><C-N><C-w>l", { desc = "Terminal right window nav" })
  map("t", "<C-x>", "<C-\\><C-n>", { desc = "Exit terminal mode" })
  
  map("n", "<leader>ti", M.show_terminal_info, { desc = "Terminal info" })
  map("n", "<leader>tg", M.create_git_terminal, { desc = "Git terminal" })
  map("n", "<leader>td", M.create_dev_terminal, { desc = "Dev server terminal" })
  map("n", "<leader>tt", M.create_test_terminal, { desc = "Test terminal" })
  map("n", "<leader>tc", M.create_claude_terminal, { desc = "Claude terminal" })
  map("n", "<leader>tr", M.run_project_command, { desc = "Run project command" })
  map("n", "<leader>ts", M.send_line_to_terminal, { desc = "Send line to terminal" })
  map("v", "<leader>ts", M.send_selection_to_terminal, { desc = "Send selection to terminal" })
  map("n", "<leader>tn", M.rename_terminal, { desc = "Rename terminal" })
  map("n", "<leader>tK", M.kill_all_terminals, { desc = "Kill all terminals" })
  map("n", "<leader>tp", M.pick_terminal, { desc = "Pick terminal" })
  map("n", "<leader>tX", M.kill_all_tmux_sessions, { desc = "Kill all tmux sessions" })
end

return M