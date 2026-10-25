-- Compact navigation inspired by established tonal active-indicator patterns.
local Nav = {}

function Nav.install(Engine, assign)
    local Theme = require("ui.themes")
    local Tabbar = require("ui.themes.widgets.tabbar")
    local BB = require("ffi/blitbuffer")
    local Box = require("ui.themes.widgets.box")
    local Icon = require("ui.themes.widgets.icon")
    local Text = require("ui.themes.widgets.text")
    local Tap = require("ui.themes.widgets.tap")
    local Render = require("mooncolor_render")
    local Center = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    local Horizontal = require("ui/widget/horizontalgroup")
    local Vertical = require("ui/widget/verticalgroup")
    local Span = require("ui/widget/verticalspan")
    local Line = require("ui/widget/linewidget")
    local GestureRange = require("ui/gesturerange")
    local old_height, old_widget = Tabbar.height, Tabbar.widget

    assign(Tabbar, "height", function()
        if not Engine.installed or not Engine.config().enabled then return old_height() end
        return Theme.px(Engine.config().navbar_labels and 64 or 48)
    end)
    assign(Tabbar, "widget", function(opts)
        if not Engine.installed or not Engine.config().enabled then
            local widget = old_widget(opts)
            widget.paintTo = Render.wrap(widget.paintTo)
            return widget
        end
        local conf, t = Engine.config(), Theme.current()
        local height = opts.height or Tabbar.height()
        local rule = math.max(1, Theme.px(1))
        local cell_h = height - rule
        local row = Horizontal:new{ align = "top" }
        local colored = conf.tabs and Engine.active()
        local accent = colored and Engine.accent("navigation") or BB.Color8(0)
        for i, tab in ipairs(opts.tabs) do
            local current = tab
            local active = current.id == opts.active
            local width = math.floor(i * opts.width / #opts.tabs) - math.floor((i-1) * opts.width / #opts.tabs)
            local icon_size = math.min(t.control.icon + 2, 28)
            local badge_w = math.max(1, math.min(Theme.px(64), width - Theme.px(8)))
            local badge_h = math.min(Theme.px(32), cell_h)
            local ink = active and accent or BB.Color8(opts.plain and 0 or t.color.faint)
            local pill = active and conf.navbar_style == "pill"
            local badge = Box:new{
                style = { bg = pill and (colored and Engine.tint(0.18,"navigation") or 0xEE) or nil,
                    border = pill and 1 or 0, border_color = pill and (colored and Engine.accentToken("navigation") or 0) or 0,
                    radius = pill and 999 or 0 },
                width = badge_w, height = badge_h,
                Icon.widget{ name = current.icon, size = icon_size, color = ink, _moon_preserve_color = true },
            }
            local stack = Vertical:new{ align = "center", badge }
            if conf.navbar_labels then
                stack[#stack + 1] = Span:new{ width = Theme.px(3) }
                local label = Text.line("caption", current.text, {
                    width = math.max(1, width - Theme.px(6)), bold = active,
                })
                label.fgcolor = ink
                stack[#stack + 1] = label
            end
            if active and conf.navbar_style == "line" then
                stack[#stack + 1] = Span:new{ width = Theme.px(3) }
                stack[#stack + 1] = Line:new{
                    dimen = Geom:new{ w = math.min(badge_w, Theme.px(28)), h = Theme.px(3) }, background = accent,
                }
            end
            local tap
            tap = Tap.wrap(Center:new{ dimen = Geom:new{ w = width, h = cell_h }, stack }, function()
                if not active and opts.on_tab then opts.on_tab(current.id, tap.dimen) end
            end)
            if not conf.navbar_labels then
                tap.ges_events.MoonNavHold = {
                    GestureRange:new{ ges = "hold", range = function() return tap.dimen end }, args = tap,
                }
                function tap:onMoonNavHold(owner)
                    if owner ~= nil and owner ~= self then return end
                    require("ui.themes.widgets.toast"):new{ text = current.text }:show()
                    return true
                end
            end
            row[#row + 1] = tap
        end
        local widget = Vertical:new{
            align = "left",
            Line:new{ dimen = Geom:new{ w = opts.width, h = rule }, background = accent }, row,
        }
        widget.paintTo = Render.wrap(widget.paintTo)
        return widget
    end)
end

return Nav
