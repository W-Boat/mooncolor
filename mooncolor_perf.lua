local Perf={}
function Perf.install(Engine,assign,replaceLocal)
    -- Discover only module-owned function upvalues. Validate every knob before
    -- publishing changes; unknown upstream layouts keep their original behavior.
    local ok,Core=pcall(require,"ui.themes.widgets.image.core")
    Engine.coverage.cover_queue=false
    if ok then
        local knobs,seen={},{}
        local wanted={BUDGET_MS={fast=8},YIELD_S={fast=.015},BITMAP_BUDGET={fast=16*1024*1024}}
        local function visit(fn)
            if seen[fn]then return end;seen[fn]=true
            local info=debug.getinfo(fn,"S")
            if not info or not info.source:gsub("\\","/"):match("/ui/themes/widgets/image/core%.lua$")then return end
            for i=1,100 do
                local name,value=debug.getupvalue(fn,i);if not name then break end
                if wanted[name]and type(value)=="number"then knobs[name]={fn=fn,index=i,original=value}
                elseif type(value)=="function"then visit(value)end
            end
        end
        for _,fn in pairs(Core)do if type(fn)=="function"then visit(fn)end end
        if knobs.BUDGET_MS and knobs.YIELD_S and knobs.BITMAP_BUDGET then
            local initialized=false
            local function tune()
                local fast=Engine.config().enabled and Engine.config().fast_covers
                for name,item in pairs(knobs)do
                    local value=fast and wanted[name].fast or item.original
                    -- Installation undo covers these private upvalue changes.
                    if not initialized then replaceLocal(item.fn,item.index,value)
                    else debug.setupvalue(item.fn,item.index,value)end
                end
                initialized=true
            end
            tune()
            local reload=Engine.reload
            assign(Engine,"reload",function(...)reload(...);tune()end)
            Engine.coverage.cover_queue=true
        end
    end
    -- Cache statistics data, not widget trees. No ownership/lifecycle changes.
    local db_ok,DB=pcall(require,"book.stats_db")
    if db_ok then
        for _,entry in ipairs{{"desktop.pages.home.heatmap","dailyBySource"},
            {"desktop.pages.home.tiles","dailyBySource"},{"desktop.pages.home.stats","dailyBySource"}}do
            local loaded,mod=pcall(require,entry[1])
            if loaded then
                local reads=DB[entry[2]]
                if type(reads)=="function"then
                    local cache,order={},{}
                    local cached=setmetatable({}, {__index=DB})
                    cached[entry[2]]=function(...)
                        if not Engine.config().enabled or not Engine.config().fast_home then return reads(...)end
                        local args={...};local parts={os.date("%Y-%m-%d")}
                        for i=1,select("#",...)do
                            local arg=args[i]
                            if type(arg)=="table"then
                                local ids={};for j,id in ipairs(arg)do ids[j]=tostring(id)end
                                table.sort(ids);parts[#parts+1]="scope:"..table.concat(ids,",")
                            else parts[#parts+1]=type(arg)..":"..tostring(arg)end
                        end
                        -- Date windows use os.time(); bucket to a minute for reuse
                        -- only within home views; no shared DB method replacement.
                        for i,arg in ipairs(args)do if type(arg)=="number"and arg>1000000000 then parts[i+1]="ts:"..math.floor(arg/60)end end
                        local key=table.concat(parts,"|")
                        local hit=cache[key]
                        if hit and os.time()-hit.at<2 then return hit.data end
                        local result=reads(...)
                        if type(result)=="table"then
                            if #order>=8 then cache[table.remove(order,1)]=nil end
                            if not cache[key]then order[#order+1]=key end
                            cache[key]={at=os.time(),data=result}
                        end
                        return result
                    end
                    local seen={}
                    local function visit(fn)
                        if seen[fn]then return end;seen[fn]=true
                        local info=debug.getinfo(fn,"S")
                        if not info or not info.source:gsub("\\","/"):find("/desktop/pages/home/",1,true)then return end
                        for i=1,100 do
                            local name,value=debug.getupvalue(fn,i);if not name then break end
                            if name=="StatsDB"and value==DB then replaceLocal(fn,i,cached)
                            elseif type(value)=="function"then visit(value)end
                        end
                    end
                    for _,fn in pairs(mod)do if type(fn)=="function"then visit(fn)end end
                    -- Invalidate before the original stats event handler compares data.
                    local handler=mod.onEvent
                    assign(mod,"onEvent",function(self,event,...)
                        if event=="stats_changed"or event=="home_refresh"or event=="detail_dirty"then cache,order={},{}end
                        if handler then return handler(self,event,...)end
                    end)
                    -- Expire on return from reading too: missed/background events
                    -- must not keep yesterday's or a closed book's data alive.
                    local activate=mod.onActivate
                    assign(mod,"onActivate",function(self,...)
                        cache,order={},{}
                        if activate then return activate(self,...)end
                    end)
                end
            end
        end
    end
end
return Perf
