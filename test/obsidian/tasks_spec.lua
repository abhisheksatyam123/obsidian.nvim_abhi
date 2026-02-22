---@diagnostic disable: invisible

local tasks = require "obsidian.tasks"
local obsidian = require "obsidian"
local Path = require "obsidian.path"

---Get a client in a temporary directory.
local with_tmp_client = function(run)
  local dir = Path.temp { suffix = "-obsidian" }
  dir:mkdir { parents = true }
  local client = obsidian.new_from_dir(tostring(dir))
  
  -- Mock obsidian.get_client to return our tmp client
  local old_get_client = obsidian.get_client
  obsidian.get_client = function() return client end

  local ok, err = pcall(run, client)

  obsidian.get_client = old_get_client
  dir:rmtree()
  if not ok then error(err) end
end

describe("obsidian.tasks parsing engine", function()
  describe("M.parse_task_line() with priorities", function()
    it("should extract #p1 priority", function()
      local t = tasks.parse_task_line("- [ ] Urgent fix #p1", 0)
      assert.are_equal(1, t.priority)
      assert.is_false(t.deferred)
    end)

    it("should extract #p2 priority", function()
      local t = tasks.parse_task_line("- [/] High priority #p2", 1)
      assert.are_equal(2, t.priority)
    end)

    it("should extract #p3 priority", function()
      local t = tasks.parse_task_line("- [|] Low priority #p3", 2)
      assert.are_equal(3, t.priority)
    end)

    it("should extract #deferred status", function()
      local t = tasks.parse_task_line("- [-] Someday #deferred", 3)
      assert.is_true(t.deferred)
      assert.is_nil(t.priority)
    end)

    it("should handle multiple tags but pick pX", function()
      local t = tasks.parse_task_line("- [ ] Multi tags #work #p1 #urgent", 4)
      assert.are_equal(1, t.priority)
    end)
  end)
end)

describe("obsidian.tasks priority & deferral mutators", function()
  describe("M.set_priority()", function()
    it("should add a priority tag to a plain task", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] Simple task" })
      tasks.set_priority(bufnr, 0, 1)
      local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
      assert.are_equal("- [ ] Simple task #p1", line)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should swap #p2 for #p1", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] Task #p2" })
      tasks.set_priority(bufnr, 0, 1)
      local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
      assert.are_equal("- [ ] Task #p1", line)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it("should remove priority when p_level is nil", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] Task #p3" })
      tasks.set_priority(bufnr, 0, nil)
      local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
      assert.are_equal("- [ ] Task", line)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe("M.defer_task()", function()
    it("should remove priorities, add #deferred and mark [-]", function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] Urgent thing #p1" })
      tasks.defer_task(bufnr, 0)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.are_equal("- [-] Urgent thing #deferred", lines[1])
      assert.is_truthy(string.find(lines[2], "💤 Deferred:"))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)

describe("obsidian.tasks focus-driven automation", function()
  describe("M.smart_toggle() auto-pause behavior", function()
    it("should call pause_all_active when starting a task", function()
      with_tmp_client(function(_)
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "- [ ] New task" })
        
        -- Spy on pause_all_active
        local original_pause = tasks.pause_all_active
        local pause_called = false
        local pause_reason = nil
        tasks.pause_all_active = function(_, _, reason, _, _)
          pause_called = true
          pause_reason = reason
          return 0, 0
        end

        tasks.smart_toggle(bufnr, 0)
        
        assert.is_true(pause_called)
        assert.are_equal("context_switch", pause_reason)

        tasks.pause_all_active = original_pause
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end)
    end)
  end)
end)

describe("obsidian.tasks time & duration helpers", function()
  it("should calculate minutes correctly", function()
    local t1 = os.time{year=2024, month=2, day=22, hour=10, min=0, sec=0}
    local t2 = os.time{year=2024, month=2, day=22, hour=11, min=15, sec=0}
    assert.are_equal(75, tasks.calc_duration_minutes(t1, t2))
  end)

  it("should format durations elegantly", function()
    assert.are_equal("45m", tasks.format_duration(45))
    assert.are_equal("1h", tasks.format_duration(60))
    assert.are_equal("1h15m", tasks.format_duration(75))
    assert.are_equal("2h30m", tasks.format_duration(150))
  end)

  it("should parse timestamps and format them back", function()
    local str = "2024-02-22 14:30"
    local epoch = tasks.parse_timestamp(str)
    assert.is_not_nil(epoch)
    assert.are_equal(str, tasks.format_timestamp(epoch))
  end)
end)

describe("obsidian.tasks buffer-aware context switching", function()
  it("should pause active tasks in unsaved buffers during context switch", function()
    with_tmp_client(function(client)
      -- Create Note 1 and open in buffer
      local note1_path = client.dir / "Note1.md"
      local bufnr1 = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr1, tostring(note1_path))
      vim.api.nvim_buf_set_lines(bufnr1, 0, -1, false, { "- [/] Task in Note 1", "  > 🟢 Started: 2026-02-22 10:00" })

      -- Create Note 2 and open in buffer
      local note2_path = client.dir / "Note2.md"
      local bufnr2 = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr2, tostring(note2_path))
      vim.api.nvim_buf_set_lines(bufnr2, 0, -1, false, { "- [ ] Task in Note 2" })

      -- Action: Start task in Note 2
      vim.api.nvim_set_current_buf(bufnr2)
      tasks.smart_toggle(bufnr2, 0)

      -- Verification: Note 1 should be paused in buffer (even though not saved to disk)
      local lines1 = vim.api.nvim_buf_get_lines(bufnr1, 0, -1, false)
      assert.are_equal("- [|] Task in Note 1", lines1[1])
      assert.is_truthy(string.find(lines1[3], "🔄 Context Switched:"))

      -- Verification: Note 2 is now active
      local lines2 = vim.api.nvim_buf_get_lines(bufnr2, 0, -1, false)
      assert.are_equal("- [/] Task in Note 2", lines2[1])

      -- Cleanup
      vim.api.nvim_buf_delete(bufnr1, { force = true })
      vim.api.nvim_buf_delete(bufnr2, { force = true })
    end)
  end)

  it("should handle line shifts when multiple tasks in the same note are toggled", function()
    with_tmp_client(function(client)
      local note_path = client.dir / "ShiftTest.md"
      local bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, tostring(note_path))
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "- [ ] task 1",
        "- [ ] task 2",
        "- [ ] task 3",
      })

      -- 1. Start task 1
      tasks.smart_toggle(bufnr, 0)
      -- State now:
      -- - [/] task 1
      --   > Started ...
      -- - [ ] task 2
      -- - [ ] task 3

      -- 2. Start task 3 (this should pause task 1)
      -- Task 3 is originally at line 2 (0-indexed), but now it's at line 3 because of the log.
      -- The user interacts with line 3.
      tasks.smart_toggle(bufnr, 3)

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- Verify task 1 is paused
      assert.are_equal("- [|] task 1", lines[1])
      -- Verify task 2 is still todo
      assert.are_equal("- [ ] task 2", lines[4])
      -- Verify task 3 is active and has its own started log
      assert.are_equal("- [/] task 3", lines[5])
      assert.is_truthy(string.find(lines[6], "Started:"))

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
