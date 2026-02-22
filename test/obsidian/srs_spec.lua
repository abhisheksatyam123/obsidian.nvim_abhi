local srs = require "obsidian.srs"
local Path = require "obsidian.path"
local async = require "plenary.async"


describe("obsidian.srs.parse_card_line()", function()
  it("should parse basic cards", function()
    local q, a, is_reversed = srs.parse_card_line("What is the capital of France? :: Paris")
    assert.equals("What is the capital of France?", q)
    assert.equals("Paris", a)
    assert.equals(false, is_reversed)
  end)

  it("should parse reversed cards", function()
    local q, a, is_reversed = srs.parse_card_line("Is Paris the capital of France? ::: Yes")
    assert.equals("Is Paris the capital of France?", q)
    assert.equals("Yes", a)
    assert.equals(true, is_reversed)
  end)

  it("should ignore lines with just text", function()
    local q, a, is_reversed = srs.parse_card_line("What is the capital of France?")
    assert.is_nil(q)
    assert.is_nil(a)
    assert.equals(false, is_reversed)
  end)

  it("should strip scheduling comments from the answer", function()
    local q, a, is_reversed = srs.parse_card_line("What is the capital of France? :: Paris <!--SR:!2025-02-15,3,250-->")
    assert.equals("What is the capital of France?", q)
    assert.equals("Paris", a)
    assert.equals(false, is_reversed)
  end)
end)

describe("obsidian.srs.parse_cloze_line()", function()
  it("should parse basic cloze", function()
    local q, a, cloze_num = srs.parse_cloze_line("The capital of France is {{c1::Paris}}.")
    assert.equals("The capital of France is [...].", q)
    assert.equals("Paris", a)
    assert.equals(1, cloze_num)
  end)

  it("should parse implicit bold cloze", function()
    local q, a, cloze_num = srs.parse_cloze_line("The capital of France is **Paris**.")
    assert.equals("The capital of France is [...].", q)
    assert.equals("Paris", a)
    assert.equals(1, cloze_num)
  end)

  it("should parse implicit highlight cloze", function()
    local q, a, cloze_num = srs.parse_cloze_line("The capital of France is ==Paris==.")
    assert.equals("The capital of France is [...].", q)
    assert.equals("Paris", a)
    assert.equals(1, cloze_num)
  end)

  it("should return nil if no cloze", function()
    local q, a, cloze_num = srs.parse_cloze_line("The capital of France is Paris.")
    assert.is_nil(q)
    assert.is_nil(a)
    assert.is_nil(cloze_num)
  end)
end)

describe("obsidian.srs schedule parsing", function()
  it("should strip schedule comments", function()
    assert.equals("Paris", srs.strip_schedule_comment("Paris <!--SR:!2025-02-15,3,250-->"))
    assert.equals("Paris", srs.strip_schedule_comment("Paris<!--SR:!2025-02-15,3,250-->"))
    assert.equals("Paris", srs.strip_schedule_comment("Paris \t <!--SR:!2025-02-15,3,250-->"))
    assert.equals("Paris", srs.strip_schedule_comment("Paris <!--SR:-2025-02-15,3,250-->"))
  end)

  it("should parse schedule comments correctly into groups", function()
    local date, interval, ease = srs.parse_schedule_comment("<!--SR:!2025-02-15,3,250-->")
    assert.equals("2025-02-15", date)
    assert.equals(3, interval)
    assert.equals(250, ease)
  end)

  it("should fail parsing malformed schedule comments", function()
    local date, interval, ease = srs.parse_schedule_comment("<!--SR:!2025-02-15,3-->")
    assert.is_nil(date)
    assert.is_nil(interval)
    assert.is_nil(ease)
  end)

  it("should rebuild a schedule comment correctly", function()
    assert.equals("<!--SR:!2025-03-01,10,240-->", srs.build_schedule_comment("2025-03-01", 10, 240))
  end)
end)

describe("obsidian.srs.card_from_line() multi-line parsing", function()
  it("should parse a basic multi-line card", function()
    local lines = {
      "What are the three main components of a Wi-Fi 802.11 frame?",
      "?",
      "1. MAC Header",
      "2. Frame Body",
      "3. Frame Check Sequence (FCS)",
      "",
      "Some other text"
    }
    local card = srs.card_from_line("?", "test.md", 2, lines)
    assert.is_not_nil(card)
    assert.equals("What are the three main components of a Wi-Fi 802.11 frame?", card.question)
    assert.equals("1. MAC Header\n2. Frame Body\n3. Frame Check Sequence (FCS)", card.answer)
    assert.equals(false, card.is_reversed)
    assert.equals(5, card.answer_end_line)
  end)

  it("should parse a reversed multi-line card", function()
    local lines = {
      "Neovim `leader` key",
      "??",
      "A prefix key used to trigger custom commands.",
      "<!--SR:!2025-02-15,3,250-->",
      "",
      "More notes..."
    }
    local card = srs.card_from_line("??", "test.md", 2, lines)
    assert.is_not_nil(card)
    assert.equals("Neovim `leader` key", card.question)
    assert.equals("A prefix key used to trigger custom commands.", card.answer)
    assert.equals(true, card.is_reversed)
    assert.equals("2025-02-15", card.due_date)
    assert.equals(3, card.interval)
    assert.equals(250, card.ease)
    assert.equals(4, card.answer_end_line)
  end)
end)

describe("obsidian.srs.sm2()", function()
  it("should reset interval when rating 'again' (grade = 1)", function()
    local new_interval, new_ease = srs.sm2(1, 10, 250)
    assert.equals(1, new_interval)
    -- Failed grade (<3) directly subtracts 20 from ease: 250 - 20 = 230
    assert.equals(230, new_ease)
  end)

  it("should bump interval to 1 on first successful review", function()
    local new_interval, new_ease = srs.sm2(4, 0, 250)
    assert.equals(1, new_interval)
    assert.equals(250, new_ease)
  end)

  it("should bump interval to 6 on second successful review", function()
    local new_interval, new_ease = srs.sm2(4, 1, 250)
    assert.equals(6, new_interval)
  end)

  it("should multiply interval by ease for later successful reviews", function()
    local new_interval, new_ease = srs.sm2(4, 6, 250)
    assert.equals(15, new_interval)
  end)

  it("should bottom out ease at MIN_EASE", function()
    local new_interval, new_ease = srs.sm2(1, 5, 140)
    assert.equals(1, new_interval)
    assert.equals(130, new_ease)
  end)
end)

describe("obsidian.srs due date calculation", function()
  it("should recognize when a card is due", function()
    assert.equals(true, srs.is_due("2020-01-01"))
  end)

  it("should compute correct days until due", function()
    local expected = -1 * math.huge
    local today_time = os.time()
    -- Create exactly midnight tomorrow
    local tomorrow_date = os.date("%Y-%m-%d", today_time + 86400)
    local diff = srs.days_until_due(tomorrow_date)
    -- Depending on exactly when in the day this is run, diff can sometimes be 0 due to 
    -- time truncations or 1. If tomorrow date string is parsed back, and it's 23:59 right now,
    -- floor(diff) might be 0. We'll simply check that diff is >= 0
    assert.is_true(diff >= 0 and diff <= 1)
  end)
end)

local with_tmp_dir = function(run)
  local dir = Path.temp { suffix = "-obsidian-srs" }
  dir:mkdir { parents = true }

  local ok, err = pcall(run, dir)

  dir:rmtree()

  if not ok then
    error(err)
  end
end

describe("obsidian.srs file integration:", function()
  local file1 = "card_test.md"

  it("should find and parse cards correctly from a directory", function()
    with_tmp_dir(function(dir)
      local src = io.open("test/fixtures/notes/srs.md", "r")
      local content = src:read("*a")
      src:close()
      
      local f = io.open(tostring(dir / file1), "w")
      f:write(content)
      f:close()

      -- Using async integration function
      srs.find_cards_async(tostring(dir), function(cards)
        assert.equals(4, #cards)

        table.sort(cards, function(a, b)
          return a.line_num < b.line_num
        end)

        assert.equals("First q", cards[1].question)
        assert.equals("First a", cards[1].answer)
        assert.equals(false, cards[1].is_reversed)
        assert.is_nil(cards[1].due_date)
        assert.is_true(cards[1].is_new)
        assert.equals(0, cards[1].interval)
        assert.equals(10, cards[1].line_num)
        
        assert.equals("Second q", cards[2].question)
        assert.equals("Second a", cards[2].answer)
        assert.equals(true, cards[2].is_reversed)
        assert.equals("2020-01-01", cards[2].due_date)
        assert.equals(250, cards[2].ease)
        assert.equals(10, cards[2].interval)
        assert.is_false(cards[2].is_new)
        assert.equals(12, cards[2].line_num)

        assert.equals("What are the three main components of a Wi-Fi 802.11 frame?", cards[3].question)
        assert.equals("1. MAC Header\n2. Frame Body\n3. Frame Check Sequence (FCS)", cards[3].answer)
        assert.equals(false, cards[3].is_reversed)
        assert.is_nil(cards[3].due_date)
        assert.equals(23, cards[3].line_num)
        assert.equals(26, cards[3].answer_end_line)

        assert.equals("Neovim `leader` key", cards[4].question)
        assert.equals("A prefix key used to trigger custom commands.", cards[4].answer)
        assert.equals(true, cards[4].is_reversed)
        assert.equals("2025-02-15", cards[4].due_date)
        assert.equals(250, cards[4].ease)
        assert.equals(3, cards[4].interval)
        assert.equals(29, cards[4].line_num)
        assert.equals(31, cards[4].answer_end_line)
      end, {})
    end)
  end)

  it("should find cloze cards using find_cloze_cards_async", function()
    with_tmp_dir(function(dir)
      local src = io.open("test/fixtures/notes/srs.md", "r")
      local content = src:read("*a")
      src:close()
      
      local f = io.open(tostring(dir / file1), "w")
      f:write(content)
      f:close()

      srs.find_cloze_cards_async(tostring(dir), function(cards)
        assert.equals(2, #cards)

        table.sort(cards, function(a, b)
          return a.line_num < b.line_num
        end)

        assert.equals("Test [...].", cards[1].question)
        assert.equals("cloze match", cards[1].answer)
        assert.equals(1, cards[1].cloze_num)

        assert.equals(14, cards[1].line_num)

        assert.equals("2025-01-01", cards[2].due_date)
        assert.equals(16, cards[2].line_num)
      end, {})
    end)
  end)

  it("review_card should rewrite the file with new scheduling info", function()
    with_tmp_dir(function(dir)
      local src = io.open("test/fixtures/notes/srs.md", "r")
      local content = src:read("*a")
      src:close()
      
      local f = io.open(tostring(dir / file1), "w")
      f:write(content)
      f:close()

      local card = srs.card_from_line("First q :: First a", tostring(dir / file1), 10)

      local res = srs.review_card(card, "good")
      assert.is_true(res)

      assert.is_not_nil(card.due_date)
      assert.equals(1, card.interval)
      assert.equals(250, card.ease)

      -- Reload file to ensure write succeeded
      local f2 = io.open(tostring(dir / file1), "r")
      local line = f2:read("*a")
      f2:close()
      
      -- The line should now have the schedule block appended.
      assert.is_true(string.match(line, "First q :: First a %<%!%-%-SR:%!%d%d%d%d%-%d%d%-%d%d%,1%,250%-%-%>") ~= nil)
    end)
  end)

  it("review_card should safely update a multiline block file with new scheduling info on the last answer line", function()
    with_tmp_dir(function(dir)
      local src = io.open("test/fixtures/notes/srs.md", "r")
      local content = src:read("*a")
      src:close()
      
      local f = io.open(tostring(dir / file1), "w")
      f:write(content)
      f:close()

      local lines = vim.split(content, "\n")
      local card = srs.card_from_line("?", tostring(dir / file1), 23, lines)
      assert.is_not_nil(card)

      local res = srs.review_card(card, "good")
      assert.is_true(res)

      assert.is_not_nil(card.due_date)
      assert.equals(1, card.interval)
      assert.equals(250, card.ease)

      -- Reload manually parsed lines to assert modification happened at line 26 specifically without touching 23
      local new_lines = {}
      for l in io.lines(tostring(dir / file1)) do
        table.insert(new_lines, l)
      end

      -- Line 23 should just be the question mark
      assert.equals("?", new_lines[23])
      -- Line 26 should append the SR schedule block
      assert.is_true(string.match(new_lines[26], "3%. Frame Check Sequence %(FCS%) %<%!%-%-SR:%!%d%d%d%d%-%d%d%-%d%d%,1%,250%-%-%>") ~= nil)
    end)
  end)
end)
