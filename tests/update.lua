-- Real updater + installer, virtualized filesystem/transport/worker boundaries.
-- Hashes are computed by Python hashlib rather than hardcoded acceptance.
local paths={
    "mooncolor_update","mooncolor_install","http.request","http.mirror","http.timeout",
    "ui/network/manager","workers.job","libs/libkoreader-lfs","utils.paths","utils.extension",
    "json","ffi/sha2","ui.themes.widgets.toast","ui.themes.widgets.progress_dialog",
    "ui.themes.widgets.confirm","ui.themes.widgets.text_viewer",
}
local function scenario(fn)
    local originals={}
    for _,name in ipairs(paths)do originals[name]=package.loaded[name]end
    local UI=require("ui/uimanager")
    local old={time=os.time,open=io.open,remove=os.remove,rename=os.rename,
        schedule=UI.scheduleIn,unschedule=UI.unschedule,next=UI.nextTick,broadcast=UI.broadcastEvent}
    local settings_copy={};for k,v in pairs(saved)do settings_copy[k]=v end
    local c={fs={},requests=0,downloads=0,installs=0,restarts=0,cancelled=0,messages={},dialogs={},
        timers={},clock=100000,network=true,payload="verified-update-archive",entries={}}
    local function mkdir(path)
        if path==""then return end
        local parent=path:match("^(.*)/[^/]+$")
        if parent and parent~=""and not c.fs[parent]then mkdir(parent)end
        c.fs[path]={mode="directory"}
    end
    local function write(path,data)
        mkdir(path:match("^(.*)/[^/]+$")or"")
        c.fs[path]={mode="file",data=data,size=#data}
    end
    c.write=write
    local root="/plugins/mooncolor.koplugin"
    write(root.."/main.lua","old version")
    write(root.."/stale.lua","old leftover")
    c.root=root
    local function attr(path,field)
        local node=c.fs[path];if not node then return nil end
        if field then return node[field]end
        return node
    end
    package.loaded["libs/libkoreader-lfs"]={
        attributes=attr,symlinkattributes=attr,mkdir=function(path)mkdir(path);return true end,
        rmdir=function(path)c.fs[path]=nil;return true end,
        dir=function(path)
            local names={".",".."};local prefix=path.."/"
            for key in pairs(c.fs)do
                if key:sub(1,#prefix)==prefix then
                    local child=key:sub(#prefix+1)
                    if not child:find("/",1,true)then names[#names+1]=child end
                end
            end
            local i=0;return function()i=i+1;return names[i]end
        end,
    }
    io.open=function(path,mode)
        if mode~="rb"and mode~="r"then error("unexpected test open mode "..tostring(mode))end
        local node=c.fs[path]
        if not node or node.mode~="file"then return nil,"missing file"end
        local at=1
        return {read=function(_,n)
            if at>#node.data then return nil end
            if n=="*a"then n=#node.data end
            local data=node.data:sub(at,at+n-1);at=at+#data;return data
        end,close=function()return true end}
    end
    os.remove=function(path)c.fs[path]=nil;return true end
    os.rename=function(from,to)
        if c.failSwap and from:find("/.mooncolor.koplugin-update/",1,true)then return nil,"simulated swap failure"end
        if not c.fs[from]then return nil,"missing rename source"end
        local changed={}
        for key,node in pairs(c.fs)do
            if key==from or key:sub(1,#from+1)==from.."/"then changed[key]=node end
        end
        for key,node in pairs(changed)do c.fs[to..key:sub(#from+1)]=node;c.fs[key]=nil end
        if to==root and from:find("update",1,true)then c.installs=c.installs+1 end
        return true
    end
    os.time=function()return c.clock end
    local digest=python_sha256(c.payload)
    c.release={version="3.1.0",tag="v3.1.0",url="https://github.com/W-Boat/mooncolor/releases/tag/v3.1.0",
        download_url="https://github.com/W-Boat/mooncolor/releases/download/v3.1.0/mooncolor.koplugin-3.1.0.zip",
        size=#c.payload,sha256=digest,notes="更新",available=true}
    c.json={tag_name="v3.1.0",body="更新",assets={{
        name="mooncolor.koplugin-3.1.0.zip",size=#c.payload,digest="sha256:"..digest,
        browser_download_url=c.release.download_url}}}
    package.loaded.json={decode=function()return c.json end}
    package.loaded["ffi/sha2"]={sha256=function()
        local parts={}
        return function(data)
            if data then parts[#parts+1]=data else return python_sha256(table.concat(parts))end
        end
    end}
    c.entries={
        {path="mooncolor.koplugin/main.lua",body="new version",mode="file"},
        {path="mooncolor.koplugin/_meta.lua",body='return {version="3.1.0"}',mode="file"},
        {path="mooncolor.koplugin/moon_source.lua",body="return {}",mode="file"},
        {path="mooncolor.koplugin/mooncolor_engine.lua",body="return {}",mode="file"},
        {path="mooncolor.koplugin/mooncolor_update.lua",body="return {}",mode="file"},
        {path="mooncolor.koplugin/mooncolor_nav.lua",body="return {}",mode="file"},
        {path="mooncolor.koplugin/mooncolor_loading.lua",body="return {}",mode="file"},
        {path="mooncolor.koplugin/mooncolor_install.lua",body="return {}",mode="file"},
    }
    local archive_original=package.loaded["ffi/archiver"]
    package.loaded["ffi/archiver"]={Reader={new=function()
        return {
            open=function()return true end,close=function()end,
            iterate=function()
                local i=0
                return function()
                    i=i+1;local e=c.entries[i];if e then e.size=e.size or #(e.body or"")end;return e
                end
            end,
            extractToPath=function(_,path,dest)
                for _,entry in ipairs(c.entries)do if entry.path==path then
                    if entry.mode=="directory"then mkdir(dest)else write(dest,entry.body)end
                    return true
                end end
                return false
            end,
        }
    end}}
    package.loaded["utils.paths"]={root=function()return "/data/.moon"end,ensureDir=function(path)mkdir(path);return true end}
    package.loaded["ui/network/manager"]={isConnected=function()return c.network end}
    package.loaded["http.timeout"]={net=function(n)return n*10 end}
    package.loaded["http.mirror"]={RELEASE_PROXIES={"https://mirror.invalid/https://github.com"}}
    package.loaded["utils.extension"]={add=function(point,callback)
        assert(point=="desktop.activated");c.activate=callback
    end}
    local function handle()return {cancel=function()c.cancelled=c.cancelled+1 end}end
    package.loaded["http.request"]={
        get=function(url,opts,cb)
            c.requests=c.requests+1;c.lastURL=url
            if c.deferGet then c.getCB=cb
            else cb(c.getError and nil or"release",c.getError)end
            return handle()
        end,
        download=function(opts,path,cb)
            c.downloads=c.downloads+1;c.downloadURL=opts.url
            assert(opts.max_bytes==8*1024*1024)
            c.downloadCB=function()
                if c.downloadError then return cb(false,c.downloadError)end
                write(path,c.corrupt and"corrupt archive"or c.payload)
                if opts.on_progress then opts.on_progress(#c.payload)end
                cb(true)
            end
            if not c.deferDownload then c.downloadCB()end
            return handle()
        end,
    }
    package.loaded["workers.job"]={run=function(worker,opts)
        local run=function()
            local ok,result=pcall(worker)
            if ok then opts.on_done(result)else opts.on_failed(result)end
        end
        if c.deferJob then c.jobCB=run else run()end
        return handle()
    end}
    local function dialog(kind)
        return {new=function(_,opts)
            opts.show=function(self)c.dialogs[#c.dialogs+1]=self;c.lastDialog=self;self.kind=kind end
            opts.close=function(self)self.closed=true end
            opts.bytes=function()end;opts.set=function()end
            return opts
        end}
    end
    package.loaded["ui.themes.widgets.toast"]={new=function(_,opts)
        return {show=function()c.messages[#c.messages+1]=opts.text end}
    end}
    package.loaded["ui.themes.widgets.progress_dialog"]=dialog("progress")
    package.loaded["ui.themes.widgets.confirm"]=dialog("confirm")
    package.loaded["ui.themes.widgets.text_viewer"]=dialog("viewer")
    UI.scheduleIn=function(_,delay,callback)c.timers[#c.timers+1]={delay=delay,callback=callback}end
    UI.unschedule=function(_,callback)
        for i=#c.timers,1,-1 do if c.timers[i].callback==callback then table.remove(c.timers,i)end end
    end
    UI.nextTick=function(_,callback)callback()end
    UI.broadcastEvent=function(_,event)
        if event.handler=="onRestart"then c.restarts=c.restarts+1 end
    end
    for _,key in ipairs{"auto_update_check","auto_update_download","downloaded_update",
        "update_last_attempt_at","update_last_checked_at","update_last_error"}do saved[key]=nil end
    package.loaded.mooncolor_update=nil;package.loaded.mooncolor_install=nil
    c.Update=require("mooncolor_update")
    c.Update.init(root)
    c.Install=require("mooncolor_install")
    local ok,err=pcall(fn,c)
    Engine.suspended=false
    os.time,io.open,os.remove,os.rename=old.time,old.open,old.remove,old.rename
    UI.scheduleIn,UI.unschedule,UI.nextTick,UI.broadcastEvent=old.schedule,old.unschedule,old.next,old.broadcast
    for _,name in ipairs(paths)do package.loaded[name]=originals[name]end
    package.loaded["ffi/archiver"]=archive_original
    for key in pairs(saved)do saved[key]=nil end;for key,value in pairs(settings_copy)do saved[key]=value end
    assert(ok,err)
end
check("updater-auto-download-verifies-but-never-installs-without-confirmation",function()scenario(function(c)
    c.activate({active=true})
    assert(c.requests==0 and #c.timers==1 and c.timers[1].delay==5)
    table.remove(c.timers,1).callback()
    assert(c.requests==1 and c.downloads==1 and c.Update.cached())
    assert(not c.Update.busy()and c.installs==0 and c.restarts==0)
    assert(c.lastDialog.kind=="viewer")
    c.lastDialog.buttons[2].callback()
    assert(c.lastDialog.kind=="confirm"and c.installs==0)
    c.lastDialog.ok_callback()
    assert(c.installs==1 and c.restarts==1)
    assert(c.fs[c.root.."/main.lua"].data=="new version"and not c.fs[c.root.."/stale.lua"])
    assert(c.fs["/plugins/.mooncolor.koplugin-backup/main.lua"].data=="old version")
end)end)
check("updater-offline-disabled-and-daily-gates-do-not-poll",function()scenario(function(c)
    c.network=false;c.Update.autoCheck();assert(c.requests==0 and not saved.update_last_attempt_at)
    c.network=true;c.Update.setAuto(false);c.Update.autoCheck();assert(c.requests==0)
    c.Update.setAuto(true);c.Update.setAutoDownload(false)
    c.Update.autoCheck();c.Update.autoCheck();assert(c.requests==1 and c.downloads==0)
    c.clock=c.clock+86400;c.Update.autoCheck();assert(c.requests==2)
    assert(#c.timers==0 and c.installs==0)
end)end)
check("updater-manual-check-bypasses-daily-backoff-and-synchronous-callbacks-settle",function()scenario(function(c)
    c.Update.autoCheck();assert(not c.Update.busy())
    c.fs["/data/.moon/mooncolor-update.zip"]=nil;saved.downloaded_update=nil
    c.Update.check(function(r)assert(r.version=="3.1.0")end,false)
    assert(c.requests==2 and not c.Update.busy())
end)end)
check("updater-suspend-cancels-download-and-ignores-late-callback",function()scenario(function(c)
    c.deferDownload=true
    c.activate({active=true});table.remove(c.timers,1).callback()
    assert(c.Update.busy()and c.downloads==1)
    c.Update.onSuspend();assert(not c.Update.busy()and c.cancelled==1)
    c.downloadCB()
    assert(not c.Update.cached()and c.installs==0 and c.restarts==0)
    Engine.suspended=true;c.Update.autoCheck();assert(c.requests==1)
end)end)
check("updater-suspend-removes-delayed-check-and-exit-cancels-request",function()scenario(function(c)
    c.activate({active=true});assert(#c.timers==1)
    c.Update.onSuspend();assert(#c.timers==0)
    c.deferGet=true;c.Update.check(nil,true);assert(c.Update.busy())
    c.Update.onExit();assert(not c.Update.busy()and c.cancelled==1)
    c.getCB("late");assert(c.downloads==0)
end)end)
check("updater-reuses-downloaded-package-and-reverifies-before-install",function()scenario(function(c)
    c.Update.download(c.release,false)
    assert(c.Update.cached()and c.downloads==1)
    c.Update.download(c.release,false);assert(c.downloads==1)
    local node=c.fs["/data/.moon/mooncolor-update.zip"]
    node.data=string.rep("x",#node.data)
    c.Update.install(c.release)
    assert(c.installs==0 and c.restarts==0 and c.fs[c.root.."/main.lua"].data=="old version"and not c.Update.cached())
end)end)
check("updater-rejects-missing-checksum-foreign-url-and-oversize-release",function()scenario(function(c)
    c.json.assets[1].digest=nil;assert(not c.Update.parse("json"))
    c.json.assets[1].digest="sha256:"..c.release.sha256
    c.json.assets[1].browser_download_url="https://evil.invalid/update.zip";assert(not c.Update.parse("json"))
    c.json.assets[1].browser_download_url=c.release.download_url
    c.json.assets[1].size=9*1024*1024;assert(not c.Update.parse("json"))
    c.json.assets="malformed";assert(not c.Update.parse("json"))
    c.json.assets={false,12,"bad"};assert(not c.Update.parse("json"))
    assert(c.installs==0)
end)end)
check("updater-api-and-download-fallback-are-bounded",function()scenario(function(c)
    c.getError="network unavailable";c.Update.check(nil,true)
    assert(c.requests==2 and not c.Update.busy())
    c.downloadError="unavailable";c.Update.download(c.release,false)
    assert(c.downloads==2 and not c.Update.busy())
    assert(c.installs==0)
end)end)
check("updater-invalid-or-corrupt-download-never-becomes-ready",function()scenario(function(c)
    c.corrupt=true;c.Update.download(c.release,false)
    assert(not c.Update.cached()and c.installs==0 and c.restarts==0)
    assert(not c.Update.busy())
end)end)
check("installer-rollback-preserves-original-after-rename-failure",function()scenario(function(c)
    c.write("/data/.moon/mooncolor-update.zip",c.payload)
    c.failSwap=true
    local ok=c.Install.run("/data/.moon/mooncolor-update.zip",c.root,c.release.sha256,"3.1.0")
    assert(not ok and c.fs[c.root.."/main.lua"].data=="old version")
    assert(not c.fs["/plugins/.mooncolor.koplugin-update"])
end)end)
check("installer-rejects-traversal-symlinks-and-wrong-version-before-swap",function()scenario(function(c)
    for _,path in ipairs{"/etc/passwd","../x","mooncolor.koplugin/../x","mooncolor.koplugin\\x","C:/x","foreign/main.lua"}do
        assert(not c.Install.safeEntry{path=path,mode="file"})
    end
    assert(not c.Install.safeEntry{path="mooncolor.koplugin/link",mode="link"})
    assert(c.Install.safeEntry{path="mooncolor.koplugin/main.lua",mode="file"})
    c.write("/data/.moon/mooncolor-update.zip",c.payload)
    local ok=c.Install.run("/data/.moon/mooncolor-update.zip",c.root,c.release.sha256,"9.0.0")
    assert(not ok and c.fs[c.root.."/main.lua"].data=="old version")
end)end)
check("installer-extraction-failure-keeps-current-files-and-cleans-staging",function()scenario(function(c)
    c.entries={{path="mooncolor.koplugin/../escape.lua",mode="file",body="bad"}}
    c.write("/data/.moon/mooncolor-update.zip",c.payload)
    assert(not c.Install.run("/data/.moon/mooncolor-update.zip",c.root,c.release.sha256,"3.1.0"))
    assert(c.fs[c.root.."/main.lua"].data=="old version")
    assert(not c.fs["/plugins/.mooncolor.koplugin-update"])
end)end)
check("updater-cached-download-survives-module-reload-without-network",function()scenario(function(c)
    c.Update.download(c.release,false)
    assert(c.Update.cached())
    package.loaded.mooncolor_update=nil
    local fresh=require("mooncolor_update");fresh.init(c.root)
    c.network=false
    fresh.manualCheck()
    assert(fresh.cached()and c.lastDialog.kind=="viewer"and c.requests==0 and c.downloads==1)
    assert(c.installs==0)
end)end)
check("updater-no-timer-when-offline-recently-checked-or-disabled",function()scenario(function(c)
    c.network=false;c.Update.schedule({active=true});assert(#c.timers==0)
    c.network=true;saved.update_last_attempt_at=c.clock
    c.Update.schedule({active=true});assert(#c.timers==0)
    saved.update_last_attempt_at=nil
    c.Update.setAuto(false);c.Update.schedule({active=true});assert(#c.timers==0)
end)end)
check("updater-closed-desktop-does-not-request-or-download",function()scenario(function(c)
    local desk={active=true}
    c.activate(desk);desk.closed=true
    table.remove(c.timers,1).callback()
    assert(c.requests==0 and c.downloads==0 and c.installs==0)
end)end)
