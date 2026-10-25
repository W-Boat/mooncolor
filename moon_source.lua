-- Moon extension API v1. GPL-3.0-or-later.
local Engine = require("mooncolor_engine")
local Editor = require("mooncolor_editor")

local function toggleRow(desktop, key, title, subtitle, icon)
    return function(width)
        return require("ui.themes.widgets.row").widget{
            width = width, icon = icon or "palette", title = title, subtitle = subtitle,
            toggle = Engine.config()[key],
            callback = function() Engine.set(key, not Engine.config()[key], desktop) end,
        }
    end
end

local function entries(desktop)
    Engine.install()
    if not Engine.installed then
        return { { group = "desktop", order = 310, row = function(width)
            return require("ui.themes.widgets.row").widget{
                width = width, title = "彩墨界面未启用", subtitle = Engine.status(), enabled = false,
            }
        end } }
    end
    return { {
        group = "desktop", order = 310, id = "appearance", icon = "palette",
        title = "彩墨界面", subtitle = "给月读的按钮、选中标签和进度条加入彩色强调",
        page = { title = "Moon Color · 彩墨界面", sections = function()
            local rows = {
                toggleRow(desktop, "enabled", "启用彩墨配色", Engine.status()),
                function(width)
                    return require("ui.themes.widgets.row").widget{
                        width = width, title = "主题 · 单色 / 混色", status = Engine.themeName(), icon = "color_lens",
                        callback = function()
                            Editor.presets(Engine, desktop)
                        end,
                    }
                end,
                toggleRow(desktop, "buttons", "彩色按钮", "主按钮用深色底配白字，普通按钮用彩色边框"),
                toggleRow(desktop, "tabs", "彩色选中状态", "选中的导航标签与列表项使用强调色"),
                toggleRow(desktop, "icons", "彩色图标", "顶栏、设置页与普通按钮的主图标使用强调色"),
                toggleRow(desktop, "headings", "彩色标题", "页面标题和大号统计数字使用强调色，正文保持黑色"),
                toggleRow(desktop, "progress", "彩色进度条", "月读主题进度条使用强调色"),
                toggleRow(desktop, "statistics", "彩色统计图", "阅读热力图按深浅着色，统计柱形图使用强调色"),
                toggleRow(desktop, "navbar_labels", "显示底栏文字", "关闭后仅显示图标，长按可查看名称"),
                function(width)
                    return require("ui.themes.widgets.row").widget{
                        width = width, icon = "navigation", title = "底栏样式",
                        status = Engine.config().navbar_style == "pill" and "胶囊高亮" or "短线指示",
                        callback = function()
                            require("ui.themes.widgets.sheet"):new{ title = "底栏样式", items = {
                                { text = "胶囊高亮", callback = function() Engine.set("navbar_style", "pill", desktop) end },
                                { text = "短线指示", callback = function() Engine.set("navbar_style", "line", desktop) end },
                            } }:show()
                        end,
                    }
                end,
                toggleRow(desktop, "card_edges", "彩色卡片边框", "为卡片和弹窗描边；默认关闭，保持页面简洁"),
                toggleRow(desktop, "fast_panels", "快速面板", "关闭面板背景网纹和网纹引起的全刷，减轻顶栏、侧栏和弹窗开销"),
                toggleRow(desktop, "fast_ticket", "快速票根", "票根内容没变时直接复用上一张图，不再整屏重画，切到票根页立即出图"),
                toggleRow(desktop, "quality_refresh", "强制彩色全刷", "默认关闭；开启会增加闪屏和等待，出现残影时可手动清屏", "refresh"),
            }
            local function action(title, subtitle, callback)
                return function(width)
                    return require("ui.themes.widgets.row").widget{
                        width = width, title = title, subtitle = subtitle, icon = "palette", callback = callback,
                    }
                end
            end
            return { { title = "彩墨配色", rows = rows }, { title = "自定义主题", rows = {
                action("按部位自定义颜色", "按钮、图标、标题、导航、进度、三组统计图及边框",
                    function() Editor.colors(Engine, desktop) end),
                action("保存当前主题", "保存颜色、底栏样式和配色开关", function() Editor.save(Engine, desktop) end),
                action("我的主题", "最多保存 12 个主题", function() Editor.library(Engine, desktop) end),
                action("手动清除残影", "仅这一次全屏刷新", function()
                    require("ui/uimanager"):setDirty(desktop or "all", "full")
                end),
            } } }
        end },
    } }
end

return {
    api = 1, id = Engine.ID,
    provides = { source = false, features = {
        setting = { entries = entries },
        panel = { actions = function()
            Engine.install()
            return { {
                id = "color", title = "彩墨配色", icon = "palette", scope = "desktop",
                active = function() return Engine.installed and Engine.config().enabled end,
                run = function(ctx)
                    local owner = ctx and ctx.ui and (ctx.ui.book or ctx.ui.moon)
                    if Engine.install() then Engine.set("enabled", not Engine.config().enabled, owner and owner.desktop) end
                end,
            } }
        end },
    } },
}
