-- GPL-3.0-or-later
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MoonColor = WidgetContainer:extend{ name = "mooncolor", is_doc_only = false }

function MoonColor:init()
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    require("ui/uimanager"):nextTick(function()
        local Engine = require("mooncolor_engine")
        if Engine.install() then
            local owner = self.ui and (self.ui.book or self.ui.moon)
            Engine.refresh(owner and owner.desktop)
        end
    end)
end

function MoonColor:addToMainMenu(items)
    items.mooncolor = {
        text = "Moon Color · 彩墨界面", sorting_hint = "more_tools",
        callback = function()
            local Engine = require("mooncolor_engine")
            Engine.install()
            require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                text = "Moon Color " .. Engine.VERSION .. "\n" .. Engine.status()
                    .. "\n\n设置入口：月读 → 设置 → 桌面 → 彩墨界面。\n需要支持 moon_source.lua 扩展和 ui.themes 的月读版本。",
            })
        end,
    }
end

function MoonColor:onSuspend()
    local engine=package.loaded.mooncolor_engine
    if engine and engine.suspend then engine.suspend()end
end
function MoonColor:onResume()
    local engine=package.loaded.mooncolor_engine
    if engine and engine.resume then engine.resume()end
end
function MoonColor:onReaderReady()
    local loading=package.loaded.mooncolor_loading
    if loading and loading.finish then loading.finish()end
end
function MoonColor:onCloseDocument()
    self:onReaderReady()
end

return MoonColor
