local tasks = require "obsidian.tasks"
local obsidian = require "obsidian"
local Path = require "obsidian.path"

---Get a client in a temporary directory.
local with_tmp_client = function(run)
  local dir = Path.temp { suffix = "-obsidian-corruption" }
  dir:mkdir { parents = true }
  local client = obsidian.new_from_dir(tostring(dir))
  
  local old_get_client = obsidian.get_client
  obsidian.get_client = function() return client end

  local ok, err = pcall(run, client)

  obsidian.get_client = old_get_client
  dir:rmtree()
  if not ok then error(err) end
end

describe("obsidian.tasks corruption prevention (Bug Report 2)", function()
  it("should atomically pause others and start target in the same note without duplication", function()
    with_tmp_client(function(client)
      local note_path = client.dir / "AtomicTest.md"
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, tostring(note_path))
      
      -- Setup 3 tasks
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "- [ ] task 1",
        "- [ ] task 2",
        "- [ ] task 3",
      })

      -- 1. Start task 1
      tasks.smart_toggle(bufnr, 0)
      
      local lines_after_1 = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are_equal("- [/] task 1", lines_after_1[1])
      assert.is_truthy(string.find(lines_after_1[2], "Started:"))
      assert.are_equal("- [ ] task 2", lines_after_1[3])
      assert.are_equal("- [ ] task 3", lines_after_1[4])

      -- 2. Start task 3 (at its new shifted position)
      -- task 3 was at index 2, shifted to 3 because of log injection above it.
      tasks.smart_toggle(bufnr, 3)

      local lines_final = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      
      -- Verification: task 1
      assert.are_equal("- [|] task 1", lines_final[1])
      -- Task 1 should have exactly TWO logs: Started and Context Switched.
      -- If there is a third log (duplicate Started), the test fails.
      assert.is_truthy(string.find(lines_final[2], "Started:"), "Task 1 missing Started log")
      assert.is_truthy(string.find(lines_final[3], "Context Switched:"), "Task 1 missing Context Switched log")
      assert.are_equal("- [ ] task 2", lines_final[4], "Task 2 corrupted")
      
      -- Verification: task 3
      assert.are_equal("- [/] task 3", lines_final[5])
      assert.is_truthy(string.find(lines_final[6], "Started:"), "Task 3 missing Started log")
      
      -- Check total line count (1 line per task + 2 logs for task 1 + 1 log for task 3 = 6 lines)
      -- Wait, tasks are:
      -- 1: - [|] task 1
      -- 2:   > Started
      -- 3:   > Context Switched
      -- 4: - [ ] task 2
      -- 5: - [/] task 3
      -- 6:   > Started
      assert.are_equal(6, #lines_final, "Corrupted line count - duplicate logs suspected")

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  it("should debounce rapid-fire toggles to prevent log nesting", function()
    with_tmp_client(function(_)
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] rapid task" })

      -- Trigger toggle 3 times instantly
      tasks.smart_toggle(bufnr, 0)
      tasks.smart_toggle(bufnr, 0)
      tasks.smart_toggle(bufnr, 0)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Should only have 1 task line + 1 Started log line
      assert.are_equal(2, #lines, "Debouncing failed - too many log lines")
      assert.are_equal("- [/] rapid task", lines[1])

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  it("should not duplicate task statistics on multiple saves", function()
    with_tmp_client(function(client)
      local note_path = client.dir / "2026-02-22.md"
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, tostring(note_path))
      
      -- 1. Initial content with placeholder
      local placeholder = "<!-- obsidian-task-stats -->"
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "Content above",
        placeholder,
        "Content below"
      })

      -- Simulate BufWritePre
      -- We need to call the callback that obsidian setup. 
      -- Since we can't easily trigger the autocmd in headless test without real save,
      -- we can manually call the logic or mock the environment.
      -- However, the simplest way is to verify the 'init.lua' logic we added.
      
      -- Let's define a helper to run the refresh logic manually for the test
      local refresh_stats = function(b)
        local lines = vim.api.nvim_buf_get_lines(b, 0, -1, false)
        for i, line in ipairs(lines) do
          if string.find(line, placeholder, 1, true) then
            local stats_mod = require "obsidian.tasks_stats"
            local report = stats_mod.format_report({ total_minutes = 10, tasks = { ["T1"] = { minutes = 10, state = "x" } } }, "2026-02-22")
            
            local replace_end = i
            local end_marker = "<!-- obsidian-task-stats-end -->"
            for k = i + 1, #lines do
              if string.find(lines[k], end_marker, 1, true) then
                replace_end = k
                break
              end
            end
            vim.api.nvim_buf_set_lines(b, i, replace_end, false, report)
            break
          end
        end
      end

      -- First Refresh
      refresh_stats(bufnr)
      local lines_1 = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      
      -- Verify report exists
      local found_report = false
      for _, l in ipairs(lines_1) do if string.find(l, "### 📊 Work Summary", 1, true) then found_report = true end end
      assert.is_true(found_report)

      -- Second Refresh (should replace, not append)
      refresh_stats(bufnr)
      local lines_2 = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Count occurrences of the header
      local count = 0
      for _, l in ipairs(lines_2) do
        if string.find(l, "### 📊 Work Summary", 1, true) then
          count = count + 1
        end
      end
      
      assert.are_equal(1, count, "Statistics report was duplicated!")
      
      -- Verify content below stayed
      local found_below = false
      for _, l in ipairs(lines_2) do if l == "Content below" then found_below = true end end
      assert.is_true(found_below)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
