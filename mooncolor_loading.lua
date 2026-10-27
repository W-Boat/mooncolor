-- One opening card per document. Read Moon metadata once, use local covers only,
-- no downloads, document extraction, polling, animation or synthetic progress.
local Loading={}
local current
local function text(value)
    if type(value)=="table"then
        local names={}
        for _,name in ipairs(value)do if type(name)=="string"and name~=""then names[#names+1]=name end end
        value=table.concat(names," · ")
    end
    if type(value)~="string"then return nil end
    value=value:match("^%s*(.-)%s*$")
    return value~=""and value or nil
end
function Loading.metadata(file,props,with_cover)
    local book,identity={},nil
    local ok,Store=pcall(require,"book.store")
    if ok and type(Store.identityFor)=="function"then
        local found,id=pcall(Store.identityFor,file)
        if found and type(id)=="table"then identity=id;book=id.book or{}end
    end
    props=props or{}
    local base=tostring(file or""):match("([^/\\]+)$")or"图书"
    base=base:gsub("%.[^%.]+$","")
    local meta={title=text(book.title)or text(props.display_title)or text(props.title)or base,
        authors=text(book.authors)or text(props.authors)or"作者未记录",file=file}
    if with_cover==false then return meta end
    local lfs=require("libs/libkoreader-lfs")
    local function localFile(path)
        if type(path)~="string"or path:match("^%a[%w+.-]*://")then return end
        local valid,mode=pcall(lfs.attributes,path,"mode")
        return valid and mode=="file"and path or nil
    end
    if identity and identity.source_id and identity.stable_id then
        local Paths=require("utils.paths")
        if type(Paths.coverPath)=="function"then
            local found,path=pcall(Paths.coverPath,identity.stable_id,identity.source_id)
            if found then meta.cover=localFile(path)end
        end
    end
    meta.cover=meta.cover or localFile(book.cover_url)or localFile(book.cover)
    if not meta.cover then
        local Download=package.loaded["ui.themes.widgets.image.download"]
        local url=text(book.cover_url)or text(book.cover)
        if url and Download and type(Download.cached)=="function"then
            local found,path=pcall(Download.cached,url)
            if found then meta.cover=localFile(path)end
        end
    end
    return meta
end
-- Read Moon's public cache/fallback interface only. Never call ensure/fetch:
-- opening a document must not wait for a quote request or repaint for its reply.
function Loading.quote()
    local ok,Hitokoto=pcall(require,"online.hitokoto")
    if not ok or type(Hitokoto)~="table"then return end
    local function read(fn,owner)
        if type(fn)~="function"then return end
        local good,data=pcall(fn,owner)
        if not good or type(data)~="table"then return end
        local body=text(data.text)
        if not body then return end
        local source=text(data.source)
        if not source then
            local author,title=text(data.author),text(data.title)
            source=author and title and(author.." · "..title)or author or title
        end
        return {text=body,source=source}
    end
    return read(Hitokoto.current,Hitokoto)or read(Hitokoto.fallback)
end
function Loading.make(file,metadata)
    local Modal=require("ui.themes.widgets.modal")
    local Theme=require("ui.themes")
    local VG=require("ui/widget/verticalgroup")
    local VS=require("ui/widget/verticalspan")
    local CC=require("ui/widget/container/centercontainer")
    local Geom=require("ui/geometry")
    local Text=require("ui.themes.widgets.text")
    local Box=require("ui.themes.widgets.box")
    local Progress=require("ui.themes.widgets.progress")
    local splash=Modal:new{covers_fullscreen=true,close_on_tap=false,dismissable=false}
    local width=math.floor(splash.dimen.w*.72)
    local h=splash.dimen.h
    local cover_h=math.max(48,math.floor(h*.27))
    local cover_w=math.floor(cover_h*2/3)
    local show_cover=require("mooncolor_engine").config().loading_style~="simple"
    local meta=metadata or Loading.metadata(file,nil,show_cover)
    splash.book=meta
    local cover
    if show_cover and meta.cover then
        local widget
        local ok,image=pcall(function()
            widget=require("ui/widget/imagewidget"):new{file=meta.cover,
                file_do_cache=true,width=cover_w,height=cover_h,
                original_in_nightmode=true,alpha=false}
            widget:getSize()
            return widget
        end)
        if ok then cover=image elseif widget and widget.free then pcall(widget.free,widget)end
    end
    splash.has_cover=cover and true or false
    local quote=show_cover and not cover and Loading.quote()or nil
    splash.quote=quote
    splash.bar=Progress:new{width=width,percent=0}
    splash.detail=Text.line("caption","正在准备阅读",{width=width})
    splash.detail_frame=Box:new{style={bg=255},width=width,height=Theme.px(36),splash.detail}
    local gap=math.max(4,math.floor(h*.018))
    local function centered(widget)
        return CC:new{dimen=Geom:new{w=width,h=widget:getSize().h},widget}
    end
    local group=VG:new{align="center",
        centered(Text.line("caption","moonflow · 月读",{width=width})),
        VS:new{width=gap*2},
    }
    if cover then
        group[#group+1]=CC:new{dimen=Geom:new{w=width,h=cover_h},cover}
        group[#group+1]=VS:new{width=gap*2}
    elseif quote then
        local quotation=VG:new{align="center",
            Text.box("body",quote.text,width,{align="center",max_lines=5})}
        if quote.source then
            local source=quote.source:match("^——")and quote.source or("—— "..quote.source)
            quotation[#quotation+1]=VS:new{width=gap}
            quotation[#quotation+1]=centered(Text.line("caption",source,{width=width,color=Theme.current().color.muted}))
        end
        group[#group+1]=CC:new{dimen=Geom:new{w=width,h=math.max(cover_h,quotation:getSize().h)},quotation}
        group[#group+1]=VS:new{width=gap*2}
    end
    group[#group+1]=Text.box("title",meta.title,width,{align="center",max_lines=2})
    group[#group+1]=VS:new{width=gap}
    group[#group+1]=centered(Text.line("caption",meta.authors,{width=width,color=Theme.current().color.muted}))
    group[#group+1]=VS:new{width=gap*3};group[#group+1]=splash.bar
    group[#group+1]=VS:new{width=gap};group[#group+1]=splash.detail_frame
    splash:setPanel(Box:new{style={bg=255},width=splash.dimen.w,height=h,group})
    splash.onTapModal=function()return true end
    splash.onSwipeModal=function()return true end
    return splash
end
local function sameFile(file)
    if not current or current.file~=file or current.closed then return false end
    local screen=require("device").screen
    return current.style==require("mooncolor_engine").config().loading_style
        and current.splash.dimen.w==screen:getWidth()and current.splash.dimen.h==screen:getHeight()
end
function Loading.finish()
    local state=current
    current=nil
    if not state or state.closed then return end
    state.closed=true
    local UI=require("ui/uimanager")
    if state.timer then UI:unschedule(state.timer);state.timer=nil end
    if state.shown then UI:close(state.splash,"ui");state.shown=false end
    if state.owner then
        state.owner._moon_loading=nil
        state.owner._moon_loading_at,state.owner._moon_loading_percent=nil,nil
    end
    if state.splash then state.splash:free();state.splash=nil end
end
local function begin(file,props)
    if sameFile(file)then return current end
    Loading.finish()
    local state={file=file,style=require("mooncolor_engine").config().loading_style}
    state.splash=Loading.make(file,Loading.metadata(file,props,state.style~="simple"))
    current=state
    local splash=state.splash
    local paint=splash.paintTo
    splash.paintTo=function(self,...)
        local result=paint(self,...)
        if not state.painted then
            state.last_at=require("socket").gettime()
            state.last_percent=0
        end
        state.painted=true
        return result
    end
    splash.onShow=function(self)
        if state.closed or state.timer then return end
        state.shown=true
        state.timer=function()
            state.timer=nil
            if not state.closed then
                -- KOReader's timeout=0 opening notice leaves the stack before
                -- blocking engine work. Keep the layout owned by this session.
                require("ui/uimanager"):close(self,"ui")
                state.shown=false
            end
        end
        require("ui/uimanager"):scheduleIn(0,state.timer)
    end
    splash.onCloseWidget=function()state.shown=false end
    return state
end
function Loading.install(Engine,assign)
    local reader_ok,Reader=pcall(require,"apps/reader/readerui")
    local rolling_ok,Rolling=pcall(require,"apps/reader/modules/readerrolling")
    Engine.coverage.loading_screen=reader_ok and rolling_ok
    if not Engine.coverage.loading_screen then return end
    local Screen=require("device").screen
    local Info=require("ui/widget/infomessage")
    local original=Reader.showReaderCoroutine
    if type(original)=="function"then
        assign(Reader,"showReaderCoroutine",function(self,file,provider,seamless)
            if seamless or Engine.suspended or not Engine.config().enabled or not Engine.config().loading_screen then
                return original(self,file,provider,seamless)
            end
            local new=Info.new
            local replaced=false
            Info.new=function(class,opts)
                if not replaced and opts and opts.timeout==0 and not opts.invisible then
                    replaced=true
                    local ok,state=pcall(begin,file)
                    if ok then return state.splash end
                end
                return new(class,opts)
            end
            local result={pcall(original,self,file,provider,seamless)}
            Info.new=new
            if not result[1]then Loading.finish();error(result[2],0)end
            return unpack(result,2)
        end)
    end
    local progress=Rolling.showEngineProgress
    if type(progress)~="function"then return end
    assign(Rolling,"showEngineProgress",function(self,percent)
        if percent==nil then Loading.finish();return progress(self,percent)end
        if Engine.suspended then return end
        if not Engine.config().enabled or not Engine.config().loading_screen
            or not self.ui or not self.ui.document or self.ui.document.been_rendered then
            return progress(self,percent)
        end
        if G_reader_settings and G_reader_settings.isFalse and G_reader_settings:isFalse("cre_show_progress")then return end
        local value=math.floor(math.max(0,math.min(1,percent))*100)
        local stamp=require("socket").gettime()
        local state=current
        local file=self.ui.document.file
        -- A new file/orientation must not inherit another book's throttle.
        if not sameFile(file)then state=nil end
        -- Cache writing may report a reverse progress tail; keep this card steady.
        if state and state.last_percent then value=math.max(value,state.last_percent)end
        if state and state.last_at then
            local change=value-state.last_percent
            if change<=0 then return end
            if value<100 and(stamp-state.last_at<1 or change<5)then return end
        end
        local ok=pcall(function()
            if not state then state=begin(file,self.ui.doc_props)end
            local splash=state.splash
            state.owner=self;self._moon_loading=splash
            splash.bar:setPercent(value)
            splash.detail:setText((value<50 and"正在读取"or"正在排版").." · "..value.."%")
            if not state.painted then
                splash:paintTo(Screen.bb,0,0)
                Screen:refreshUI(0,0,Screen:getWidth(),Screen:getHeight())
            else
                local bar,detail=splash.bar.dimen,splash.detail_frame.dimen
                local height=math.min(Screen:getHeight()-bar.y,detail.y+detail.h-bar.y)
                Screen.bb:paintRect(bar.x,bar.y,bar.w,height,require("ffi/blitbuffer").COLOR_WHITE)
                splash.bar:paintTo(Screen.bb,bar.x,bar.y)
                splash.detail_frame:paintTo(Screen.bb,detail.x,detail.y)
                Screen:refreshUI(bar.x,bar.y,bar.w,height)
            end
            state.last_at,state.last_percent=stamp,value
            self._moon_loading_at,self._moon_loading_percent=stamp,value
        end)
        if not ok then Loading.finish();return progress(self,percent)end
    end)
    -- Exit, errors and password prompts must never leave an owned loading image.
    for _,method in ipairs{"showFileManager","unlockDocumentWithPassword"}do
        local fn=Reader[method]
        if type(fn)=="function"then assign(Reader,method,function(self,...)
            Loading.finish();return fn(self,...)
        end)end
    end
end
return Loading
