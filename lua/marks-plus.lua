local m = {}

local config = {
	existing_window = nil,
	keybind_popup_close = '<ESC>',
	keybind_popup_delete_mark = '<CR>',
	popup_current_file_text = 'CURRENT_FILE',
	popup_show_local_first = false,
	popup_sort_by_line_number = false
}

function m.setup(opts)
	if not opts then return end
	if opts.keybind_popup_close then
		config.keybind_popup_close = opts.keybind_popup_close
	end
	if opts.keybind_popup_delete_mark then
		config.keybind_popup_delete_mark = opts.keybind_popup_delete_mark
	end

	if opts.popup_current_file_text then
		config.popup_current_file_text = opts.popup_current_file_text
	end

	if opts.popup_show_local_first then
		config.popup_show_local_first = opts.popup_show_local_first
	end

	if opts.popup_sort_by_line_number then
		config.popup_sort_by_line_number = opts.popup_sort_by_line_number
	end
end

---@param tab table
---@return table
local function reverse_marklist(tab)
	local new_tab = {}
	for i = 1, #tab do
		table.insert(new_tab, tab[#tab + 1 - i])
	end
	return new_tab
end

---Jump to the next mark
---@param lowercase boolean
---@param reverse boolean
local function next_mark(lowercase, reverse)
	local ascii_start = 64
	if lowercase then ascii_start = 96 end
	local cur_line = vim.api.nvim_win_get_cursor(0)
	local cur_buffer = vim.api.nvim_get_current_buf()
	local available_marks = {}
	local cur_pos_mark = { mark_name = nil, internal_number = nil }
	--Loop through all letters
	for i = 1, 26 do
		local mark_char = nil
		local mark_pos = {}
		if (lowercase) then
			mark_char = string.char(ascii_start + i)
			mark_pos = vim.api.nvim_buf_get_mark(0, mark_char)
			mark_pos[3] = cur_buffer
		else
			mark_char = string.char(ascii_start + i)
			mark_pos = vim.api.nvim_get_mark(mark_char, {})
		end

		--Does mark exist?
		if mark_pos[1] ~= 0 then --mark_pos[4] ~= '-invalid-' and mark_pos[4] ~= 'existing_window = nil' then
			--Mark on same line as cursor?
			if (mark_pos[1] == cur_line[1] and mark_pos[3] == cur_buffer) then
				cur_pos_mark.mark_name = mark_char
				cur_pos_mark.internal_number = ascii_start + i
			else
				table.insert(available_marks, {
					mark_name = mark_char,
					pos = mark_pos[1],
					buf = mark_pos[3],
					internal_number = (ascii_start + i)
				})
			end
		end
	end

	if reverse then
		available_marks = reverse_marklist(available_marks)
	end

	--Case 1: cursor not on mark
	if cur_pos_mark.mark_name == nil then
		local nearest_mark_same_buffer = { internal_number = nil, diff = 0 }
		--Get nearest mark in buffer in relation to current line
		for _, val in ipairs(available_marks) do
			if val.buf == cur_buffer then
				local diff_lines = 0
				if cur_line[1] > val.pos then
					diff_lines = cur_line[1] - val.pos
				else
					diff_lines = val.pos - cur_line[1]
				end
				if nearest_mark_same_buffer.diff == 0 or diff_lines < nearest_mark_same_buffer.diff then
					nearest_mark_same_buffer.internal_number = val.internal_number
					nearest_mark_same_buffer.diff = diff_lines
				end
			end
		end

		if nearest_mark_same_buffer.internal_number ~= nil then
			--Move to next letter based on nearest mark
			for _, val in ipairs(available_marks) do
				if (not reverse and val.internal_number > nearest_mark_same_buffer.internal_number) or
					(reverse and val.internal_number < nearest_mark_same_buffer.internal_number) then
					local success = pcall(vim.cmd.echo, "'" .. val.mark_name)
					if success then return end
				end
			end
			--No mark bigger -> Just move to first mark in table that is not the nearest mark
			for _, val in ipairs(available_marks) do
				if val.internal_number ~= nearest_mark_same_buffer.internal_number then
					local success = pcall(vim.cmd.echo, "'" .. val.mark_name)
					if success then return end
				end
			end
		end
		--Otherwise just move to first letter found (no marks in current buffer)
		for _, val in ipairs(available_marks) do
			local success = pcall(vim.cmd.echo, "'" .. val.mark_name)
			if success then return end
		end
	else
		--Case 2: Cursor on mark
		--Move to next letter based on mark on current line
		for _, val in ipairs(available_marks) do
			if (not reverse and val.internal_number > cur_pos_mark.internal_number) or
				(reverse and val.internal_number < cur_pos_mark.internal_number) then
				local success = pcall(vim.cmd.echo, "'" .. val.mark_name)
				if success then return end
			end
		end
		--No mark bigger -> Just move to first mark in table that is not the current mark
		for _, val in ipairs(available_marks) do
			if val.internal_number ~= cur_pos_mark.internal_number then
				local success = pcall(vim.cmd.echo, "'" .. val.mark_name)
				if success then return end
			end
		end
	end
end

---@param lowercase boolean
local function set_next_mark(lowercase)
	local from = lowercase and 'a' or 'A'
	local to = lowercase and 'z' or 'Z'
	for i = string.byte(from), string.byte(to) do
		local mark = string.char(i)

		local pos = vim.fn.getpos("'" .. mark)

		if pos[2] == 0 then
			-- mark at current cursor position
			vim.cmd("mark " .. mark)
			return
		end
	end

	vim.notify("No available global marks (A–Z)", vim.log.levels.WARN)
end

---@return table
local function get_global_marks()
	local marks = vim.fn.getmarklist()
	local global_marks = {}

	for _, mark in ipairs(marks) do
		if mark.mark:match("'%u") then -- Uppercase = global
			table.insert(global_marks, mark)
		end
	end
	return global_marks
end

---@return table
local function get_local_marks()
	local marks = vim.fn.getmarklist(vim.api.nvim_get_current_buf())
	local local_marks = {}

	for _, mark in ipairs(marks) do
		if mark.mark:match("'%l") then
			table.insert(local_marks, mark)
		end
	end
	return local_marks
end

---Show floating popup to display marks
---@param marklist table
---@param popup_title string
local function popup_delete_marks(marklist, popup_title)
	if #marklist == 0 then
		vim.notify('No marks set', vim.log.levels.INFO)
		return
	end

	if config.existing_window and vim.api.nvim_win_is_valid(config.existing_window) then
		vim.api.nvim_set_current_win(config.existing_window)
		return
	end
	config.existing_window = nil

	local original_buffer = vim.api.nvim_get_current_buf()

	-- Sort by mark name
	table.sort(marklist, function(a, b)
		local a_is_local = a.mark:match("'%l") ~= nil
		local b_is_local = b.mark:match("'%l") ~= nil

		if a_is_local ~= b_is_local then
			if config.popup_show_local_first then
				return a_is_local
			else
				return not a_is_local
			end
		end

		if config.popup_sort_by_line_number then
			return a.pos[2] < b.pos[2]
		end

		return a.mark < b.mark
	end)

	-- Format output
	local lines = { popup_title }
	table.insert(lines, string.rep("-", 60))

	for _, mark in ipairs(marklist) do
		local line
		if mark.file then
			line = string.sub(mark.mark, 2, 2) .. ' ' .. mark.file .. ' ' .. mark.pos[2]
		else
			line = string.sub(mark.mark, 2, 2) .. ' ' .. config.popup_current_file_text .. ' ' .. mark.pos[2]
		end
		table.insert(lines, line)
	end


	-- Calculate window dimensions
	local width = math.min(80, vim.o.columns - 4)
	local height = math.min(#lines + 2, vim.o.lines - 4)

	-- Create popup buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("buflisted", false, { buf = buf })

	-- Configure floating window
	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		style = "minimal",
		border = "rounded",
	}

	-- Handle deletion of marks in popup window
	local function on_button_press(popup_buffer, source_buffer)
		local win = vim.api.nvim_get_current_win()
		local row = vim.api.nvim_win_get_cursor(win)[1]
		local line = vim.api.nvim_buf_get_lines(popup_buffer, row - 1, row, false)[1]
		if row < 3 then return end
		local mark_to_delete = string.sub(line, 1, 1)

		local check
		if mark_to_delete:match("%l") then
			check = pcall(vim.api.nvim_buf_del_mark, source_buffer, mark_to_delete)
		else
			check = pcall(vim.api.nvim_del_mark, mark_to_delete)
		end

		if not check then
			vim.notify("Could not delete mark: " .. mark_to_delete, vim.log.levels.WARN)
			return
		end

		vim.api.nvim_set_option_value("modifiable", true, { buf = popup_buffer })
		vim.api.nvim_buf_set_lines(popup_buffer, row - 1, row, false, {})
		vim.api.nvim_set_option_value("modifiable", false, { buf = popup_buffer })

		if vim.api.nvim_buf_line_count(popup_buffer) == 2 then
			vim.api.nvim_win_close(win, true)
		end
	end

	local win = vim.api.nvim_open_win(buf, true, opts)
	config.existing_window = win
	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	vim.keymap.set("n", config.keybind_popup_close, function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, {
		buffer = buf,
		nowait = true,
		noremap = true,
		silent = true,
	})
	vim.keymap.set("n", config.keybind_popup_delete_mark, function()
		on_button_press(buf, original_buffer)
	end, {
		buffer = buf,
		noremap = true,
		nowait = true,
		silent = true,
	})

	local group = vim.api.nvim_create_augroup("MarkDelAugroup Buffer " .. buf, {
		clear = true,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			if not vim.api.nvim_win_is_valid(win) then
				return
			end

			local leaving_win = vim.api.nvim_get_current_win()

			if leaving_win ~= win then
				return
			end

			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_close(win, true)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		buffer = buf,
		once = true,
		callback = function()
			pcall(vim.api.nvim_del_augroup_by_id, group)
			config.existing_window = nil
		end,
	})
end

function m.jump_to_next_global_mark()
	next_mark(false, false)
end

function m.jump_to_previous_global_mark()
	next_mark(false, true)
end

function m.jump_to_next_local_mark()
	next_mark(true, false)
end

function m.jump_to_previous_local_mark()
	next_mark(true, true)
end

function m.set_next_local_mark()
	set_next_mark(true)
end

function m.set_next_global_mark()
	set_next_mark(false)
end

function m.popup_delete_global_marks()
	local marklist = get_global_marks()
	popup_delete_marks(marklist, 'GLOBAL MARKS')
end

function m.popup_delete_local_marks()
	local marklist = get_local_marks()
	popup_delete_marks(marklist, 'LOCAL MARKS')
end

function m.popup_delete_all_marks()
	local marklist_local = get_local_marks()
	local marklist = get_global_marks()
	for _, mark_local in ipairs(marklist_local) do
		table.insert(marklist, mark_local)
	end
	popup_delete_marks(marklist, 'ALL MARKS')
end

return m
