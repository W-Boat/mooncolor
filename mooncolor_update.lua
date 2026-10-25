-- Follows the Moon/ko-games update workflow, reusing Moon HTTP, mirrors,
-- workers and themed dialogs. Background download never authorizes installation.
local Update={REPO="W-Boat/mooncolor",MAX_BYTES=8*1024*1024,INTERVAL=86400}
local ID="ext.mooncolor"
local moduleRoot=debug.getinfo(1,"S").source:gsub("\\","/"):match("^@(.*)/[^/]+$")
local UI=require("ui/uimanager")
local op,ready,scheduled,offered,desktop,initialized,root
local function settings()return require("utils.settings").getSource(ID)end
local function save()require("utils.settings").saveSource(ID)end
local function version()return require("mooncolor_engine").VERSION end
local function awake()return not require("mooncolor_engine").suspended end
local function connected()
    local ok,network=pcall(require,"ui/network/manager")
    if not ok then return false end
    local success,on=pcall(network.isConnected,network)
    return success and on==true
end
local function archivePath()
    return require("utils.paths").root().."/mooncolor-update.zip"
end
local function notice(message)
    require("ui.themes.widgets.toast"):new{text=message,timeout=4}:show()
end
local function firstLine(err)return tostring(err):match("[^\r\n]*")end
function Update.newer(a,b)
    if type(a)~="string"or type(b)~="string"then return false end
    local left,right={a:match("^v?(%d+)%.(%d+)%.(%d+)$")},{b:match("^(%d+)%.(%d+)%.(%d+)$")}
    if #left~=3 or #right~=3 then return false end
    for i=1,3 do if tonumber(left[i])~=tonumber(right[i])then return tonumber(left[i])>tonumber(right[i])end end
    return false
end
local function validRelease(r)
    if type(r)~="table"or type(r.version)~="string"or #r.version>32
        or not r.version:match("^%d+%.%d+%.%d+$")then return false end
    local tag=r.tag
    if tag~=r.version and tag~="v"..r.version then return false end
    local name="mooncolor.koplugin-"..r.version..".zip"
    local expected="https://github.com/"..Update.REPO.."/releases/download/"..tag.."/"..name
    return r.download_url==expected and type(r.size)=="number"and r.size>0
        and r.size<=Update.MAX_BYTES and r.size==math.floor(r.size)
        and type(r.sha256)=="string"and #r.sha256==64 and r.sha256:match("^%x+$")~=nil
end
function Update.parse(body)
    local ok,data=pcall(require("json").decode,body)
    if not ok or type(data)~="table"or data.draft or data.prerelease then return nil,"无效的更新响应"end
    local v=type(data.tag_name)=="string"and data.tag_name:match("^v?(%d+%.%d+%.%d+)$")
    if not v or #v>32 then return nil,"未找到稳定版本"end
    local name="mooncolor.koplugin-"..v..".zip"
    for _,asset in ipairs(type(data.assets)=="table"and data.assets or{})do
        if type(asset)=="table"and asset.name==name then
            local digest=type(asset.digest)=="string"and asset.digest:match("^sha256:("..("%x"):rep(64)..")$")
            local r={version=v,tag=data.tag_name,url="https://github.com/"..Update.REPO.."/releases/tag/"..data.tag_name,
                download_url=asset.browser_download_url,size=tonumber(asset.size),sha256=digest and digest:lower(),
                notes=type(data.body)=="string"and data.body or""}
            if validRelease(r)then r.available=Update.newer(v,version());return r end
            return nil,"更新包地址、大小或 SHA-256 无效"
        end
    end
    return nil,"新版本缺少 Moon Color 安装包"
end
function Update.autoEnabled()return settings().auto_update_check~=false end
function Update.autoDownload()return settings().auto_update_download~=false end
function Update.busy()return op~=nil end
local function releaseDialog(operation)
    if operation and operation.dialog then operation.dialog:close();operation.dialog=nil end
end
function Update.cancel()
    if op and op.phase=="installing"then return false end
    local previous=op;op=nil
    if previous then
        if previous.job and previous.job.cancel then previous.job:cancel()end
        releaseDialog(previous)
        if previous.phase~="checking"then
            pcall(os.remove,archivePath()..".part")
            if not ready then pcall(os.remove,archivePath())end
        end
    end
    return true
end
function Update.setAuto(on)
    settings().auto_update_check=on==true;save()
    if not on and op and op.automatic then Update.cancel()end
end
function Update.setAutoDownload(on)
    settings().auto_update_download=on==true;save()
    if not on and op and op.automatic and op.phase=="downloading"then Update.cancel()end
end
local function track(operation,phase,start)
    operation.phase=phase
    local leg={};operation.leg=leg;operation.job=nil
    local ok,job=pcall(start,function()return op==operation and operation.leg==leg end)
    if not ok then
        if op==operation then
            op=nil;releaseDialog(operation)
            if not operation.automatic then notice("更新失败："..firstLine(job))end
        end
        return
    end
    -- HTTP open/fork failures may call back synchronously. Do not resurrect an
    -- ended operation or overwrite the next stage's handle with the old one.
    if op==operation and operation.leg==leg then operation.job=job end
end
local function fail(operation,reason)
    if op~=operation then return end
    op=nil;releaseDialog(operation)
    settings().update_last_error=firstLine(reason);save()
    if not operation.automatic then notice("更新失败："..firstLine(reason))end
end
function Update.cached()
    local r=ready or settings().downloaded_update
    if not validRelease(r)or not Update.newer(r.version,version())then return nil end
    local attr=require("libs/libkoreader-lfs").attributes(archivePath())
    if not attr or tonumber(attr.size)~=r.size then return nil end
    return r
end
function Update.status()
    if op then return ({checking="正在检查",downloading="正在下载",verifying="正在校验",installing="正在安装"})[op.phase]or"更新中"end
    local r=Update.cached()
    return r and("已下载 "..r.version)or("当前 "..version())
end
local function canPrompt()
    return awake()and desktop and desktop.active and not desktop.closed
end
function Update.offer(r,downloaded,manual)
    if not awake()or(not manual and not canPrompt())then return end
    local key=r.version..(downloaded and":ready"or":available")
    if not manual and offered==key then return end
    offered=key
    local dialog
    dialog=require("ui.themes.widgets.text_viewer"):new{
        title=downloaded and"更新已下载"or"发现新版本",
        text="Moon Color "..version().." → "..r.version.."\n\n"
            ..(downloaded and"安装包已下载。安装前会再次校验 SHA-256，完成后重启 KOReader。\n\n"or"下载后仍需确认安装。\n\n")
            ..(r.notes or""),
        buttons={
            {text="稍后",callback=function()dialog:close()end},
            {text=downloaded and"安装并重启"or"下载更新",variant="primary",callback=function()
                dialog:close()
                if downloaded then Update.confirmInstall(r)else Update.download(r,false)end
            end},
        },
    }
    dialog:show()
end
function Update.check(callback,automatic)
    if op then if not automatic then notice("已有更新任务正在运行")end;return false end
    if not awake()or not connected()then if not automatic then notice("请先连接网络后检查更新")end;return false end
    local operation={automatic=automatic==true};op=operation
    settings().update_last_attempt_at=os.time();save()
    if not automatic then
        operation.dialog=require("ui.themes.widgets.progress_dialog"):new{
            title="检查更新",text="正在检查 Moon Color 更新…",dismissable=false,on_cancel=Update.cancel}
        operation.dialog:show()
    end
    local urls={
        "https://api.github.com/repos/"..Update.REPO.."/releases/latest",
        "https://api.ankio.net/gh/repos/"..Update.REPO.."/releases/latest",
    }
    local function fetch(i)
        track(operation,"checking",function(alive)
            return require("http.request").get(urls[i],{
                timeout=require("http.timeout").net(1),
                headers={Accept="application/vnd.github+json",["X-GitHub-Api-Version"]="2022-11-28"},
            },function(body,err)
                if not alive()then return end
                local r,reason
                if not err then r,reason=Update.parse(body)end
                if (err or not r)and urls[i+1]then fetch(i+1);return end
                op=nil;releaseDialog(operation)
                if not r then
                    settings().update_last_error=firstLine(err or reason);save()
                    if not automatic then notice("检查失败："..firstLine(err or reason))end
                    if callback then callback(nil,err or reason)end
                    return
                end
                local s=settings();s.update_last_checked_at=os.time();s.update_last_error=nil;save()
                if callback then callback(r)end
            end)
        end)
    end
    fetch(1)
    return true
end
local function mirrors(r)
    local urls={r.download_url}
    local ok,Mirror=pcall(require,"http.mirror")
    if ok then
        for _,prefix in ipairs(Mirror.RELEASE_PROXIES or{})do
            if type(prefix)=="string"and prefix:match("^https://")and #urls<3 then
                urls[#urls+1]=prefix..r.download_url:sub(#"https://github.com"+1)
            end
        end
    end
    return urls
end
function Update.download(r,automatic)
    if not validRelease(r)or not Update.newer(r.version,version())then notice("更新信息无效");return false end
    if op then if not automatic then notice("已有更新任务正在运行")end;return false end
    if not awake()or not connected()then if not automatic then notice("请先连接网络")end;return false end
    local cached=Update.cached()
    if cached and cached.sha256==r.sha256 then Update.offer(cached,true,not automatic);return true end
    local Paths=require("utils.paths")
    local made,err=Paths.ensureDir(Paths.root())
    if not made then if not automatic then notice("无法准备下载目录："..firstLine(err))end;return false end
    ready=nil
    local operation={automatic=automatic==true};op=operation
    settings().downloaded_update=nil;save()
    if not automatic then
        operation.dialog=require("ui.themes.widgets.progress_dialog"):new{
            title="下载 Moon Color "..r.version,dismissable=false,on_cancel=Update.cancel}
        operation.dialog:show()
    end
    local urls=mirrors(r)
    local function attempt(i)
        os.remove(archivePath())
        track(operation,"downloading",function(alive)
            return require("http.request").download({
                url=urls[i],timeout=require("http.timeout").net(10),allow_redirects=true,max_bytes=Update.MAX_BYTES,
                on_progress=function(bytes)
                    if alive()and operation.dialog then operation.dialog:bytes(bytes,r.size)end
                end,
            },archivePath(),function(ok,why)
                if not alive()then return end
                if not ok then
                    if urls[i+1]then attempt(i+1)else fail(operation,why)end
                    return
                end
                track(operation,"verifying",function(valid)
                    return require("workers.job").run(function()
                        local attr=require("libs/libkoreader-lfs").attributes(archivePath())
                        if not attr or tonumber(attr.size)~=r.size then error("download size mismatch",0)end
                        local verified,reason=require("mooncolor_install").verify(archivePath(),r.sha256)
                        if not verified then error(reason,0)end
                        return true
                    end,{name="mooncolor.update.verify",kind="light",timeout=30,
                        on_done=function()
                            if not valid()then return end
                            op=nil;releaseDialog(operation)
                            ready=r;settings().downloaded_update=r;settings().update_last_error=nil;save()
                            Update.offer(r,true,not automatic)
                        end,
                        on_failed=function(reason)
                            if not valid()then return end
                            os.remove(archivePath())
                            if urls[i+1]then attempt(i+1)else fail(operation,reason)end
                        end,
                    })
                end)
            end)
        end)
    end
    attempt(1)
    return true
end
function Update.confirmInstall(r)
    -- This function is called only by an explicit user action, never autoCheck.
    if op then notice("已有更新任务正在运行");return end
    local cached=Update.cached()
    if not cached or cached.sha256~=r.sha256 then notice("安装包不存在，请重新下载");return end
    require("ui.themes.widgets.confirm"):new{
        title="安装 Moon Color "..r.version,ok_text="安装并重启",
        text="将替换 Moon Color 插件并重启 KOReader。主题与设置会保留，旧版目录会备份。",
        ok_callback=function()Update.install(r)end,
    }:show()
end
function Update.install(r)
    if op or not awake()then return false end
    if not root or not root:match("/mooncolor%.koplugin$")then notice("无法定位 Moon Color 插件目录");return false end
    if not validRelease(r)or not Update.newer(r.version,version())then notice("更新信息无效");return false end
    local cached=Update.cached()
    if not cached or cached.sha256~=r.sha256 then notice("请先下载更新");return false end
    local operation={};op=operation
    operation.dialog=require("ui.themes.widgets.progress_dialog"):new{
        title="安装 Moon Color 更新",text="正在校验和安装，请勿关闭设备…",dismissable=false}
    operation.dialog:show()
    track(operation,"installing",function(alive)
        return require("workers.job").run(function()
            local installed,reason=require("mooncolor_install").run(archivePath(),root,r.sha256,r.version)
            if not installed then error(reason,0)end
            return true
        end,{name="mooncolor.update.install",kind="light",timeout=120,
            on_done=function()
                if not alive()then return end
                op=nil;ready=nil;settings().downloaded_update=nil;save();os.remove(archivePath())
                operation.dialog:set("更新完成，正在重启 KOReader…",100)
                UI:nextTick(function()UI:broadcastEvent(require("ui/event"):new("Restart"))end)
            end,
            on_failed=function(reason)
                if not alive()then return end
                local error=tostring(reason)
                if error:find("checksum mismatch",1,true)or error:find("archive version mismatch",1,true)
                    or error:find("invalid archive",1,true)or error:find("not a Moon Color",1,true)then
                    ready=nil;settings().downloaded_update=nil;save();os.remove(archivePath())
                end
                fail(operation,reason)
            end,
        })
    end)
    return true
end
function Update.manualCheck()
    local cached=Update.cached()
    if cached then Update.offer(cached,true,true);return end
    Update.check(function(r)
        if not r then return end
        if not r.available then notice("已是最新版本 · "..version())
        else Update.offer(r,false,true)end
    end,false)
end
function Update.autoCheck()
    if not awake()or op or not Update.autoEnabled()then return end
    local cached=Update.cached()
    if cached then Update.offer(cached,true,false);return end
    local last=tonumber(settings().update_last_attempt_at)or 0
    local now=os.time()
    if last>0 and now-last>=0 and now-last<Update.INTERVAL then return end
    if not connected()then return end
    Update.check(function(r)
        if not r or not r.available then return end
        if Update.autoDownload()then Update.download(r,true)else Update.offer(r,false,false)end
    end,true)
end
function Update.schedule(desk)
    desktop=desk or desktop
    if scheduled or op or not Update.autoEnabled()or not awake()then return end
    local cached=Update.cached()
    if cached then
        if offered==cached.version..":ready"then return end
    else
        local last=tonumber(settings().update_last_attempt_at)or 0
        local elapsed=os.time()-last
        if (last>0 and elapsed>=0 and elapsed<Update.INTERVAL)or not connected()then return end
    end
    scheduled=require("ui.guard").wrap("Moon Color auto update",function()
        scheduled=nil
        if canPrompt()then Update.autoCheck()end
    end)
    UI:scheduleIn(5,scheduled)
end
function Update.onSuspend()
    if scheduled then UI:unschedule(scheduled);scheduled=nil end
    Update.cancel()
end
Update.onExit=Update.onSuspend
function Update.init(path)
    if path then root=path:gsub("\\","/"):gsub("/+$","")end
    root=root or moduleRoot
    if initialized then return end
    initialized=true
    require("utils.extension").add("desktop.activated",Update.schedule)
end
return Update
