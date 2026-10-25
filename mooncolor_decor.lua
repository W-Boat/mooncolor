local Decor = {}

function Decor.install(Engine, assign)
    local BB = require("ffi/blitbuffer")
    local Render = require("mooncolor_render")
    local Icon = require("ui.themes.widgets.icon")
    local Text = require("ui.themes.widgets.text")
    local icon, line = Icon.widget, Text.line
    -- Colours are cdata created through ffi.metatype, and their __eq metamethod
    -- dereferences the other operand (ffi/blitbuffer.lua:
    -- ColorRGB32_mt:__eq -> color:getColorRGB32()). LuaJIT calls that __eq even
    -- for `color == nil`, so comparing a colour against nil or a number raises
    -- "attempt to index local 'color' (a nil value)". Compare types first, and
    -- use plain truthiness to test whether a colour is set.
    local function sameColor(a, b)
        if type(a) ~= type(b) then return false end
        return a == b
    end
    -- Unset colour, or the generic black that means "let the accent show".
    local function isBlack(color)
        if not color then return true end
        if type(color) == "number" then return color == 0 end
        return sameColor(color, BB.COLOR_BLACK)
    end
    -- Only nil / numeric black mean "the caller did not pick a colour".
    local function isUnstyled(color)
        if not color then return true end
        return type(color) == "number" and color == 0
    end
    assign(Icon, "widget", function(opts)
        if Engine.active() and Engine.config().icons and not opts._moon_preserve_color
            and isBlack(opts.color) then
            local copy = {}; for k,v in pairs(opts) do copy[k]=v end
            copy.color = Engine.accent("icons")
            return icon(copy)
        end
        return icon(opts)
    end)
    assign(Text, "line", function(role, text, opts)
        local widget = line(role, text, opts)
        if Engine.active() and Engine.config().headings and (role == "title" or role == "hero")
            and (not opts or isUnstyled(opts.color)) then widget.fgcolor = Engine.accent("headings") end
        return widget
    end)

    Engine.coverage = {}
    local ok, Heatmap = pcall(require, "ui.widgets.heatmap")
    Engine.coverage.heatmap = ok
    if ok then
        local paint = Heatmap.paintTo
        local levels = { [0xC8]=0.22, [0x98]=0.45, [0x58]=0.72, [0]=1 }
        assign(Heatmap, "paintTo", function(self, bb, x, y)
            if not Engine.active() or not Engine.config().statistics then return paint(self, bb, x, y) end
            local canvas = Render.canvas(bb)
            local lut={}
            for shade,weight in pairs(levels)do lut[shade]=Engine.color(Engine.tint(weight,"stat1"))end
            local view = setmetatable({ paintRect = function(_, px, py, w, h, c)
                local gray = type(c)=="number" and c or (BB.isColor8 and BB.isColor8(c) and c.a)
                if lut[gray] then c=lut[gray] end
                return canvas:paintRect(px, py, w, h, c)
            end }, { __index = function(_, k)
                local method = canvas[k]
                if type(method)=="function" then return function(_, ...) return method(canvas, ...) end end
                return method
            end })
            return paint(self, view, x, y)
        end)
    end

    local chart_ok, Chart = pcall(require, "ui.widgets.chart")
    Engine.coverage.chart = chart_ok
    if chart_ok then
        local bars = Chart.bars
        local Line = require("ui/widget/linewidget")
        assign(Chart, "bars", function(opts)
            local widget = bars(opts)
            if Engine.active() and Engine.config().statistics then
                local function walk(w)
                    if getmetatable(w)==Line and sameColor(w.background, BB.COLOR_BLACK) then w.background = Engine.accent("stat1") end
                    for _, child in ipairs(w) do if type(child)=="table" then walk(child) end end
                end
                walk(widget)
            end
            widget.paintTo = Render.wrap(widget.paintTo)
            return widget
        end)
    end

    local book_ok, Book = pcall(require, "ui.widgets.book")
    Engine.coverage.book_badges = book_ok and type(Book.progressBadge)=="function"
    if Engine.coverage.book_badges then
        local badge = Book.progressBadge
        assign(Book, "progressBadge", function(...)
            local widget = badge(...)
            if widget and Engine.active() and Engine.config().progress then
                widget.style.bg = Engine.accentToken("progress")
                local fg=BB.Color8(Engine.foreground("progress"))
                local function textColor(w)
                    if w.fgcolor then w.fgcolor=fg end
                    for _,child in ipairs(w)do if type(child)=="table"then textColor(child)end end
                end
                textColor(widget)
            end
            return widget
        end)
    end
    require("mooncolor_home").install(Engine,assign)
    require("mooncolor_ticket").install(Engine,assign)
end

return Decor
