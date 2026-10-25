-- Opening splash + real crengine progress. No timer animation or invented ETA.
local Loading={}
function Loading.make(file)
    local Modal=require("ui.themes.widgets.modal")
    local Theme=require("ui.themes")
    local VG=require("ui/widget/verticalgroup")
    local VS=require("ui/widget/verticalspan")
    local Text=require("ui.themes.widgets.text")
    local Icon=require("ui.themes.widgets.icon")
    local Box=require("ui.themes.widgets.box")
    local Progress=require("ui.themes.widgets.progress")
    local splash=Modal:new{covers_fullscreen=true,close_on_tap=false,dismissable=false}
    local width=math.floor(splash.dimen.w*.76)
    splash.bar=Progress:new{width=width,percent=0}
    splash.detail=Text.line("caption","正在打开",{width=width})
    splash.detail_frame=Box:new{style={bg=255},width=width,height=Theme.px(40),splash.detail}
    local name=tostring(file or ""):match("([^/\\]+)$")or"图书"
    local group=VG:new{align="left",
        Icon.widget{name="auto_stories",size=56},
        VS:new{width=Theme.px(28)},
        Text.line("hero","即将开始阅读",{width=width}),
        VS:new{width=Theme.px(16)},
        Text.line("body",name,{width=width}),
        VS:new{width=Theme.px(36)},splash.bar,
        VS:new{width=Theme.px(16)},splash.detail_frame,
    }
    splash:setPanel(Box:new{style={bg=255},width=splash.dimen.w,height=splash.dimen.h,group})
    splash.onTapModal=function()return true end
    splash.onSwipeModal=function()return true end
    splash.onShow=function(self)
        -- Same lifetime as KOReader's original timeout=0 opening notice.
        require("ui/uimanager"):scheduleIn(0,function()self:close()end)
    end
    return splash
end
function Loading.install(Engine,assign)
    local reader_ok,Reader=pcall(require,"apps/reader/readerui")
    local rolling_ok,Rolling=pcall(require,"apps/reader/modules/readerrolling")
    Engine.coverage.loading_screen=reader_ok and rolling_ok
    if not Engine.coverage.loading_screen then return end
    local UI=require("ui/uimanager")
    local Screen=require("device").screen
    local Info=require("ui/widget/infomessage")
    local original=Reader.showReaderCoroutine
    local current_file
    if type(original)=="function"then
        assign(Reader,"showReaderCoroutine",function(self,file,provider,seamless)
            if seamless or not Engine.config().enabled or not Engine.config().loading_screen then
                return original(self,file,provider,seamless)
            end
            current_file=file
            -- Only the synchronous, timeout=0 opening notice is replaced. Password,
            -- unsupported-file, archive-restore and error messages remain native.
            local new=Info.new
            Info.new=function(class,opts)
                if opts and opts.timeout==0 and not opts.invisible then
                    local ok,widget=pcall(Loading.make,file)
                    if ok then return widget end
                end
                return new(class,opts)
            end
            local result={pcall(original,self,file,provider,seamless)}
            Info.new=new
            if not result[1]then error(result[2],0)end
            return unpack(result,2)
        end)
    end
    local progress=Rolling.showEngineProgress
    if type(progress)~="function"then return end
    local now=function()return require("socket").gettime()end
    assign(Rolling,"showEngineProgress",function(self,percent)
        if percent==nil then
            if self._moon_loading then self._moon_loading:free();self._moon_loading=nil end
            self._moon_loading_at,self._moon_loading_percent=nil,nil
            return progress(self,percent)
        end
        if not Engine.config().enabled or not Engine.config().loading_screen
            or not self.ui or not self.ui.document or self.ui.document.been_rendered then
            return progress(self,percent)
        end
        if G_reader_settings and G_reader_settings.isFalse and G_reader_settings:isFalse("cre_show_progress")then return end
        local value=math.floor(math.max(0,math.min(1,percent))*100)
        local stamp=now()
        if self._moon_loading_at and (stamp-self._moon_loading_at<.5 or value==self._moon_loading_percent)then return end
        local ok=pcall(function()
            local splash=self._moon_loading
            if not splash then
                splash=Loading.make(current_file or self.ui.document.file)
                self._moon_loading=splash
                splash.bar:setPercent(value)
                splash.detail:setText((value<50 and "正在读取文件"or"正在排版").."  "..value.."%")
                splash:paintTo(Screen.bb,0,0)
                Screen:refreshUI(0,0,Screen:getWidth(),Screen:getHeight())
                return
            end
            splash.bar:setPercent(value)
            splash.detail:setText((value<50 and "正在读取文件"or"正在排版").."  "..value.."%")
            -- Paint the existing component. Refresh only the progress area after
            -- the first full-screen frame; no extra bitmap or pixel scan.
            local region=splash.bar.dimen
            local detail=splash.detail_frame.dimen
            local height=math.min(Screen:getHeight()-region.y,detail.y+detail.h-region.y)
            Screen.bb:paintRect(region.x,region.y,region.w,height,require("ffi/blitbuffer").COLOR_WHITE)
            splash.bar:paintTo(Screen.bb,region.x,region.y)
            splash.detail_frame:paintTo(Screen.bb,detail.x,detail.y)
            Screen:refreshUI(region.x,region.y,region.w,height)
        end)
        if not ok then
            if self._moon_loading then pcall(self._moon_loading.free,self._moon_loading);self._moon_loading=nil end
            return progress(self,percent)
        end
        self._moon_loading_at,self._moon_loading_percent=stamp,value
    end)
end
return Loading
