check("upgrade-migrates-aggressive-cover-and-refresh-settings-once",function()
    saved.performance_schema=2;saved.fast_covers=true;saved.quality_refresh=true
    local before=saves
    Engine.reload()
    assert(not Engine.config().fast_covers and not Engine.config().quality_refresh)
    assert(saved.performance_schema==3 and saves==before+1)
    for i=1,100 do Engine.config()end
    assert(saves==before+1)
end)
check("opening-metadata-uses-Moon-identity-including-chapter-books",function()
    local Loading=require("mooncolor_loading")
    local lfs=require("libs/libkoreader-lfs")
    local attrs=lfs.attributes
    local paths=require("utils.paths")
    local coverPath=paths.coverPath
    paths.coverPath=function(id,sid)return "/covers/"..sid.."/"..id..".png"end
    lfs.attributes=function(file,field)
        if file=="/covers/online/novel.png"then return "file"end
    end
    metadata_rows["/cache/0001.epub"]={source_id="online",stable_id="novel",
        book={title="月读中的正确书名",authors={"作者甲","作者乙"},cover="https://example.invalid/a.jpg"}}
    local meta=Loading.metadata("/cache/0001.epub",{display_title="文件中的旧标题",authors="旧作者"})
    assert(meta.title=="月读中的正确书名"and meta.authors=="作者甲 · 作者乙")
    assert(meta.cover=="/covers/online/novel.png")
    local fallback=Loading.metadata("/normal/no-moon.epub",{display_title="文档标题",authors="文档作者"})
    assert(fallback.title=="文档标题"and fallback.authors=="文档作者"and not fallback.cover)
    assert(Loading.metadata("/normal/test-file.epub").title=="test-file")
    lfs.attributes=attrs;paths.coverPath=coverPath
end)
check("opening-card-is-shared-metadata-read-once-no-cover-repaint",function()
    local Loading=require("mooncolor_loading")
    Loading.finish()
    local UI=require("ui/uimanager")
    local Reader=require("apps/reader/readerui")
    local Rolling=require("apps/reader/modules/readerrolling")
    local lfs=require("libs/libkoreader-lfs")
    local attr=lfs.attributes
    lfs.attributes=function(file,field)if file=="/local-cover.png"then return "file"end end
    metadata_rows["/novel.epub"]={book={title="龙族",authors="江南",cover="/local-cover.png"}}
    local Images=require("ui/widget/imagewidget")
    local new=Images.new
    local decoded,painted,freed=0,0,0
    Images.new=function(self,opts)
        decoded=decoded+1
        local widget=new(self,opts)
        widget.paintTo=function()painted=painted+1 end
        widget.free=function()freed=freed+1 end
        return widget
    end
    local original_free=require("ui/widget/container/widgetcontainer").free
    -- The upstream test container's free is a no-op; add real recursive ownership
    -- traversal for this lifecycle case only.
    require("ui/widget/container/widgetcontainer").free=function(self)
        for _,child in ipairs(self)do if child.free then child:free()end end
    end
    local reader={}
    local before=metadata_reads
    Reader.showReaderCoroutine(reader,"/novel.epub")
    local card=reader.notice
    local card_free=card.free
    local released=0
    card.free=function(self,...)released=released+1;return card_free(self,...)end
    assert(card.book.title=="龙族"and card.book.authors=="江南")
    card:paintTo(Kit.canvas(),0,0)
    local painted_once=painted
    local Screen=Device.screen
    Screen.bb=Kit.canvas()
    local refreshes={}
    Screen.refreshUI=function(_,x,y,w,h)refreshes[#refreshes+1]={w=w,h=h}end
    local rolling={ui={document={file="/novel.epub"}}}
    clock_time=200
    Rolling.showEngineProgress(rolling,.1)
    assert(rolling._moon_loading==card and decoded==1 and metadata_reads==before+1)
    clock_time=201
    Rolling.showEngineProgress(rolling,.11)
    assert(#refreshes==1)
    clock_time=202
    Rolling.showEngineProgress(rolling,.2)
    assert(#refreshes==2 and refreshes[2].h<800 and painted==painted_once)
    Rolling.showEngineProgress(rolling,nil)
    Loading.finish()
    -- Test containers/groups don't all implement free; the state itself must
    -- release ownership exactly once regardless of nested stub behavior.
    assert(not rolling._moon_loading and released==1)
    require("ui/widget/container/widgetcontainer").free=original_free
    Images.new=new;lfs.attributes=attr
end)
check("suspend-stops-rendering-and-cleans-loading-without-radio-commands",function()
    local Loading=require("mooncolor_loading")
    Loading.finish()
    local Reader=require("apps/reader/readerui")
    local reader={}
    Reader.showReaderCoroutine(reader,"sleep.epub")
    Engine.suspend()
    assert(Engine.suspended and not Engine.active())
    local desk={updated=false,updateView=function(self)self.updated=true end}
    Engine.refresh(desk,true);assert(not desk.updated)
    local rolling={ui={document={file="sleep.epub"}}}
    require("apps/reader/modules/readerrolling").showEngineProgress(rolling,.5)
    assert(not rolling._moon_loading)
    Engine.resume()
    assert(not Engine.suspended and Engine.active())
end)
check("sleep-pauses-only-existing-Bluetooth-display-poll-and-restores-once",function()
    local old=package.loaded["features.bluetooth"]
    local BT=assert(loadstring([[
        local poll_tick=function()end
        return {watch=function()return poll_tick end,clear=function()poll_tick=nil end}
    ]],"@/plugins/book.koplugin/features/bluetooth/init.lua"))()
    package.loaded["features.bluetooth"]=BT
    local UI=require("ui/uimanager")
    local oldSchedule,oldUnschedule=UI.scheduleIn,UI.unschedule
    local scheduled,unscheduled=0,0
    UI.unschedule=function(_,fn)if fn==BT.watch()then unscheduled=unscheduled+1 end end
    UI.scheduleIn=function(_,delay,fn)assert(delay==1 and fn==BT.watch());scheduled=scheduled+1 end
    Engine.suspend();Engine.suspend()
    assert(unscheduled==1 and scheduled==0)
    Engine.resume();Engine.resume()
    assert(scheduled==1)
    Engine.suspend();BT.clear();Engine.resume()
    assert(scheduled==1)
    UI.scheduleIn,UI.unschedule=oldSchedule,oldUnschedule
    package.loaded["features.bluetooth"]=old
end)
