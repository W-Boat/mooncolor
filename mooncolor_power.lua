-- Pause Moon's display-only Bluetooth polling while suspended. Do not toggle
-- radios, write sysfs, retry suspend or add a periodic task.
local Power={}
function Power.install(Engine)
    local UI=require("ui/uimanager")
    local paused
    local function timer()
        local BT=package.loaded["features.bluetooth"]
        if type(BT)~="table"or type(BT.watch)~="function"then return end
        local info=debug.getinfo(BT.watch,"S")
        if not info or not info.source:gsub("\\","/"):match("/features/bluetooth/init%.lua$")then return end
        for i=1,100 do
            local name,value=debug.getupvalue(BT.watch,i);if not name then break end
            if name=="poll_tick"and type(value)=="function"then return BT.watch,i,value end
        end
    end
    function Engine.suspend()
        if Engine.suspended then return end
        Engine.suspended=true
        local loading=package.loaded.mooncolor_loading
        if loading and loading.finish then loading.finish()end
        if not Engine.config().enabled then return end
        local watch,index,tick=timer()
        if tick then UI:unschedule(tick);paused={watch=watch,index=index,tick=tick}end
    end
    function Engine.resume()
        if not Engine.suspended then return end
        Engine.suspended=false
        local previous=paused;paused=nil
        if previous then
            local _,current=debug.getupvalue(previous.watch,previous.index)
            -- Last subscriber may have unsubscribed during suspend.
            if current==previous.tick then
                UI:unschedule(current)
                UI:scheduleIn(1,current)
            end
        end
    end
end
return Power
