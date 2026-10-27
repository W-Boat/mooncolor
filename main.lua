-- GPL-3.0-or-later
local MoonColor=require("ui/widget/container/widgetcontainer"):extend{name="mooncolor",is_doc_only=false}
function MoonColor:init()
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self)end
    require("ui/uimanager"):nextTick(function()
        local Engine=require("mooncolor_engine")
        if not Engine.install()then return end
        local owner=self.ui and(self.ui.book or self.ui.moon)
        Engine.refresh(owner and owner.desktop)
        local Update=require("mooncolor_update")
        Update.init(self.path)
        if owner and owner.desktop then Update.schedule(owner.desktop)end
    end)
end
function MoonColor:addToMainMenu(items)
    items.mooncolor={text="Moon Color · 界面增强",sorting_hint="more_tools",callback=function()
        local Engine=require("mooncolor_engine");Engine.install()
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text="Moon Color "..Engine.VERSION.."\n"..Engine.status()
                .."\n\n月读 → 设置 → 桌面 → 底栏与开书遮罩。\n颜色请在月读官方显示设置中调整。"})
    end}
end
function MoonColor:onSuspend()
    local Update=package.loaded.mooncolor_update;if Update then Update.onSuspend()end
    local Engine=package.loaded.mooncolor_engine;if Engine then Engine.suspend()end
end
function MoonColor:onResume()
    local Engine=package.loaded.mooncolor_engine;if Engine then Engine.resume()end
end
function MoonColor:onReaderReady()
    local Loading=package.loaded.mooncolor_loading;if Loading then Loading.finish()end
end
MoonColor.onCloseDocument=MoonColor.onReaderReady
function MoonColor:onNetworkConnected()
    local Update=package.loaded.mooncolor_update;if Update then Update.schedule()end
end
function MoonColor:onExit()
    self:onReaderReady()
    local Update=package.loaded.mooncolor_update;if Update then Update.onExit()end
end
return MoonColor
