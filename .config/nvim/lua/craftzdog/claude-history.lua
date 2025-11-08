local M = {}

-- JSONデコード用のヘルパー関数
local function safe_json_decode(line)
  local ok, result = pcall(vim.fn.json_decode, line)
  if ok then
    return result
  end
  return nil
end

-- タイムスタンプをフォーマット (Unixミリ秒 or ISO 8601 -> 日時文字列)
local function format_timestamp(timestamp_ms)
  if not timestamp_ms then
    return "N/A"
  end

  -- 文字列（ISO 8601形式）の場合はそのまま返す
  if type(timestamp_ms) == "string" then
    -- ISO 8601形式 (2025-11-08T07:01:29.512Z) から読みやすい形式に変換
    local year, month, day, hour, min, sec = timestamp_ms:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if year then
      return string.format("%s-%s-%s %s:%s:%s", year, month, day, hour, min, sec)
    end
    return timestamp_ms
  end

  -- 数値の場合はUnixミリ秒として変換
  local timestamp_sec = math.floor(timestamp_ms / 1000)
  return os.date("%Y-%m-%d %H:%M:%S", timestamp_sec)
end

-- プロジェクトパスを短縮 (/Users/Manabe/xxx/yyy -> xxx/yyy)
local function shorten_project(project_path)
  if not project_path then
    return "N/A"
  end
  local home = os.getenv("HOME")
  if home and project_path:sub(1, #home) == home then
    local relative = project_path:sub(#home + 2) -- +2 for the trailing slash
    return relative
  end
  return project_path
end

-- history.jsonlを読み込んでパース
function M.read_history()
  local history_file = vim.fn.expand("~/.claude/history.jsonl")

  if vim.fn.filereadable(history_file) ~= 1 then
    vim.notify("Claude history file not found: " .. history_file, vim.log.levels.ERROR)
    return nil
  end

  local lines = vim.fn.readfile(history_file)
  local entries = {}

  for _, line in ipairs(lines) do
    if line ~= "" then
      local entry = safe_json_decode(line)
      if entry and entry.sessionId then -- sessionIdがあるもののみ
        table.insert(entries, entry)
      end
    end
  end

  -- タイムスタンプで降順ソート（最新が上）
  table.sort(entries, function(a, b)
    return (a.timestamp or 0) > (b.timestamp or 0)
  end)

  return entries
end

-- 会話詳細ファイルのパスを取得
local function get_conversation_file_path(project, session_id)
  -- プロジェクトパスをファイル名に変換 (/Users/Manabe/.config -> -Users-Manabe--config)
  -- / と . の両方を - に置き換え
  local project_name = project:gsub("[/.]", "-")
  local file_path = vim.fn.expand("~/.claude/projects/" .. project_name .. "/" .. session_id .. ".jsonl")
  return file_path
end

-- 会話詳細を読み込んで整形
function M.read_conversation_detail(project, session_id)
  local file_path = get_conversation_file_path(project, session_id)

  if vim.fn.filereadable(file_path) ~= 1 then
    return "Conversation file not found: " .. file_path
  end

  local lines = vim.fn.readfile(file_path)
  local messages = {}

  for _, line in ipairs(lines) do
    if line ~= "" then
      local entry = safe_json_decode(line)
      if entry and entry.message then
        local role = entry.message.role or "unknown"
        local content = ""

        -- contentが配列の場合とテキストの場合を処理
        if type(entry.message.content) == "table" then
          for _, part in ipairs(entry.message.content) do
            if part.type == "text" then
              content = content .. part.text .. "\n"
            elseif part.type == "tool_use" then
              content = content .. "[Tool: " .. (part.name or "unknown") .. "]\n"
            end
          end
        elseif type(entry.message.content) == "string" then
          content = entry.message.content
        end

        table.insert(messages, {
          role = role,
          content = content,
          timestamp = format_timestamp(entry.timestamp),
        })
      end
    end
  end

  -- メッセージを整形して返す
  local result = {}
  for i, msg in ipairs(messages) do
    table.insert(result, string.format("=== %s [%s] ===", msg.role:upper(), msg.timestamp))
    table.insert(result, msg.content)
    table.insert(result, "")
  end

  return table.concat(result, "\n")
end

-- 会話をプレビュー
function M.preview_conversation(entry)
  if not entry or not entry.sessionId then
    vim.notify("Invalid conversation entry", vim.log.levels.ERROR)
    return
  end

  local content = M.read_conversation_detail(entry.project, entry.sessionId)

  -- 新しいバッファを作成
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"

  -- コンテンツを分割して設定
  local lines = vim.split(content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- ウィンドウを開く
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Conversation Preview ",
    title_pos = "center",
  })

  -- qとEscで閉じる
  vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
end

-- 会話を再開（通常のNeovimターミナルを使用）
function M.resume_conversation(entry)
  if not entry or not entry.sessionId then
    vim.notify("Invalid conversation entry", vim.log.levels.ERROR)
    return
  end

  -- sessionIdを取得
  local session_id = entry.sessionId

  -- Claude CLIのパス
  local claude_cmd = vim.fn.expand("~/.claude/local/claude")

  -- cdw（現在のプロジェクトパス）を設定
  local cwd = entry.project or vim.fn.getcwd()

  -- 右側に垂直分割でターミナルを開く（ClaudeCodeと同じ位置）
  -- 35%の幅で右端に開く
  local width = math.floor(vim.o.columns * 0.35)
  vim.cmd("botright " .. width .. "vsplit")
  vim.cmd("lcd " .. vim.fn.fnameescape(cwd))
  vim.cmd("terminal " .. claude_cmd .. " --resume " .. session_id)
  vim.cmd("startinsert")

  vim.notify("Resuming conversation: " .. session_id:sub(1, 8) .. "...", vim.log.levels.INFO)
end

-- フローティングウィンドウで履歴を表示
function M.show_history()
  local entries = M.read_history()

  if not entries or #entries == 0 then
    vim.notify("No conversation history found", vim.log.levels.WARN)
    return
  end

  -- バッファを作成
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "claude-history"

  -- 表示用の行を作成
  local display_lines = {}
  local max_project_len = 0

  -- プロジェクト名の最大長を計算
  for _, entry in ipairs(entries) do
    local project = shorten_project(entry.project)
    max_project_len = math.max(max_project_len, #project)
  end

  for i, entry in ipairs(entries) do
    local timestamp = format_timestamp(entry.timestamp)
    local project = shorten_project(entry.project)
    local display = entry.display or "No description"

    -- 改行を除去してスペースに置換
    display = display:gsub("[\n\r]+", " "):gsub("%s+", " ")

    -- 60文字で切り詰め
    if #display > 60 then
      display = display:sub(1, 57) .. "..."
    end

    -- プロジェクト名をパディング
    project = project .. string.rep(" ", max_project_len - #project)

    local line = string.format("%s | %s | %s", timestamp, project, display)
    table.insert(display_lines, line)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.bo[buf].modifiable = false

  -- ウィンドウサイズを計算
  local width = math.min(vim.o.columns - 4, 120)
  local height = math.min(#display_lines + 2, math.floor(vim.o.lines * 0.8))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- フローティングウィンドウを開く
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Claude Code Conversation History ",
    title_pos = "center",
  })

  -- キーマップ設定
  local opts = { noremap = true, silent = true, buffer = buf }

  -- プレビュー
  vim.keymap.set("n", "p", function()
    local line_num = vim.api.nvim_win_get_cursor(win)[1]
    M.preview_conversation(entries[line_num])
  end, opts)

  -- 再開
  vim.keymap.set("n", "r", function()
    local line_num = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_close(win, true)
    M.resume_conversation(entries[line_num])
  end, opts)

  -- Enterでも再開
  vim.keymap.set("n", "<CR>", function()
    local line_num = vim.api.nvim_win_get_cursor(win)[1]
    vim.api.nvim_win_close(win, true)
    M.resume_conversation(entries[line_num])
  end, opts)

  -- 閉じる
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, opts)

  -- ヘルプメッセージを表示
  vim.notify("p: Preview | r/Enter: Resume | q/Esc: Close", vim.log.levels.INFO)
end

return M
