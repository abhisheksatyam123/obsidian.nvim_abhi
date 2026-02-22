local tasks_stats = require "obsidian.tasks_stats"
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

describe("obsidian.tasks_stats engine", function()
  describe("M.parse_duration_to_minutes()", function()
    it("should parse hours and minutes", function()
      assert.are_equal(105, tasks_stats.parse_duration_to_minutes("(Duration: 1h45m)"))
    end)

    it("should parse hours only", function()
      assert.are_equal(120, tasks_stats.parse_duration_to_minutes("(Duration: 2h)"))
    end)

    it("should parse minutes only", function()
      assert.are_equal(45, tasks_stats.parse_duration_to_minutes("(Duration: 45m)"))
    end)

    it("should return 0 for malformed strings", function()
      assert.are_equal(0, tasks_stats.parse_duration_to_minutes("No duration here"))
    end)
  end)

  describe("M.format_report()", function()
    it("should format a basic report correctly", function()
      local stats = {
        total_minutes = 90,
        tasks = {
          ["Task A"] = { minutes = 60, state = "x" },
          ["Task B"] = { minutes = 30, state = "/" }
        }
      }
      local report = tasks_stats.format_report(stats, "2026-02-22")
      assert.are_equal("### 📊 Work Summary (2026-02-22)", report[1])
      assert.are_equal("- **Total Time Focused**: 1h30m", report[2])
      assert.are_equal("- **Details**:", report[3])
      assert.are_equal("  - [x] Task A (1h)", report[4])
      assert.are_equal("  - [/] Task B (30m)", report[5])
    end)

    it("should return empty message when no stats", function()
      local stats = { total_minutes = 0, tasks = {} }
      local report = tasks_stats.format_report(stats, "2026-02-22")
      assert.are_equal("### 📊 Work Summary (2026-02-22)", report[1])
      assert.are_equal("_No time logs found for this date._", report[2])
    end)
  end)

  describe("M.get_daily_stats() vault-wide", function()
    it("should aggregate stats from multiple files using ripgrep", function()
      with_tmp_client(function(client)
        local vault = tostring(client.dir)
        local date = "2026-02-22"
        
        -- Create a test note with task and log
        local note1_path = client.dir / "Note1.md"
        local note1_content = [[
- [ ] Task 1
  > 🟢 Started: 2026-02-22 10:00
  > ⏸ Paused: 2026-02-22 11:00 (Duration: 1h)
]]
        local f1 = io.open(tostring(note1_path), "w")
        f1:write(note1_content)
        f1:close()

        -- Create another note with a different task
        local note2_path = client.dir / "Note2.md"
        local note2_content = [[
- [/] Task 2
  > 🟢 Started: 2026-02-22 12:00
  > ⏸ Paused: 2026-02-22 12:30 (Duration: 30m)
]]
        local f2 = io.open(tostring(note2_path), "w")
        f2:write(note2_content)
        f2:close()

        -- Run the stats aggregation
        local results = nil
        tasks_stats.get_daily_stats(vault, date, function(stats)
          results = stats
        end, true)

        assert.is_not_nil(results)
        assert.are_equal(90, results.total_minutes)
        assert.are_equal(60, results.tasks["Task 1"].minutes)
        assert.are_equal(30, results.tasks["Task 2"].minutes)
      end)
    end)
  end)
end)
