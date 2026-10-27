-- Moon-compatible staged installation, using KOReader SHA-256 and archiver.
-- No executable code is loaded from an update before directory replacement.
local Install={}
local DIR="mooncolor.koplugin"
local MAX_ZIP,MAX_UNPACKED,MAX_FILES=8*1024*1024,32*1024*1024,256
function Install.verify(path,digest)
    if type(digest)~="string"or #digest~=64 or not digest:match("^%x+$")then return nil,"invalid checksum"end
    local file,err=io.open(path,"rb")
    if not file then return nil,err end
    local hash=require("ffi/sha2").sha256()
    local count=0
    while true do
        local data=file:read(65536);if not data then break end
        count=count+#data
        if count>MAX_ZIP then file:close();return nil,"download too large"end
        hash(data)
    end
    file:close()
    if hash():lower()~=digest:lower()then return nil,"update checksum mismatch"end
    return true
end
function Install.safeEntry(entry)
    local path=entry.path
    if type(path)~="string"or path==""or path:find("\\",1,true)or path:find(":",1,true)
        or path:find("%z")or path:sub(1,1)=="/"then return false end
    for part in path:gmatch("[^/]+")do if part==".."or part=="."then return false end end
    if entry.mode and entry.mode~="file"and entry.mode~="directory"then return false end
    return path==DIR or path==DIR.."/"or path:sub(1,#DIR+1)==DIR.."/"
end
local function removeTree(path)
    local lfs=require("libs/libkoreader-lfs")
    local attr=lfs.symlinkattributes(path)
    if not attr then return true end
    if attr.mode~="directory"then return os.remove(path)end
    for name in lfs.dir(path)do
        if name~="."and name~=".."then
            local ok,err=removeTree(path.."/"..name);if not ok then return nil,err end
        end
    end
    return lfs.rmdir(path)
end
local function extract(archive,staging)
    local lfs=require("libs/libkoreader-lfs")
    local made,err=lfs.mkdir(staging);if not made then return nil,err end
    local reader=require("ffi/archiver").Reader:new()
    local ok,reason=pcall(function()
        if not reader:open(archive)then error(reader.err or"cannot open archive",0)end
        local total,count=0,0
        for entry in reader:iterate()do
            count=count+1
            total=total+math.max(0,tonumber(entry.size)or 0)
            if count>MAX_FILES or total>MAX_UNPACKED then error("archive too large",0)end
            if not Install.safeEntry(entry)then error("invalid archive path or type",0)end
            if not reader:extractToPath(entry.path,staging.."/"..entry.path)then error(reader.err or"extraction failed",0)end
        end
        if reader.err then error(reader.err,0)end
    end)
    reader:close()
    return ok or nil,reason
end
function Install.run(archive,root,digest,version)
    if type(root)~="string"or not root:match("/mooncolor%.koplugin$")or root:find("/../",1,true)then
        return nil,"invalid plugin directory"
    end
    local valid,err=Install.verify(archive,digest)
    if not valid then return nil,err end
    local lfs=require("libs/libkoreader-lfs")
    if lfs.symlinkattributes(root,"mode")~="directory"then return nil,"invalid plugin directory"end
    local parent=root:match("^(.*)/[^/]+$")
    local staging,backup=parent.."/.mooncolor.koplugin-update",parent.."/.mooncolor.koplugin-backup"
    local ok
    ok,err=removeTree(staging)
    if ok then ok,err=extract(archive,staging)end
    local nextRoot=staging.."/"..DIR
    if ok then
        for _,name in ipairs{"main.lua","_meta.lua","moon_source.lua","mooncolor_engine.lua",
            "mooncolor_nav.lua","mooncolor_loading.lua","mooncolor_update.lua","mooncolor_install.lua"}do
            if lfs.symlinkattributes(nextRoot.."/"..name,"mode")~="file"then ok,err=nil,"not a moonflow archive";break end
        end
    end
    if ok then
        local file=io.open(nextRoot.."/_meta.lua","rb")
        local meta=file and file:read(16384)or"";if file then file:close()end
        local found=meta:match('version%s*=%s*"([%d%.]+)"')or meta:match("version%s*=%s*'([%d%.]+)'")
        if found~=version then ok,err=nil,"archive version mismatch"end
    end
    if not ok then removeTree(staging);return nil,err end
    ok,err=removeTree(backup)
    if not ok then removeTree(staging);return nil,err end
    ok,err=os.rename(root,backup)
    if not ok then removeTree(staging);return nil,err end
    ok,err=os.rename(nextRoot,root)
    if not ok then
        local restored,why=os.rename(backup,root)
        removeTree(staging)
        if not restored then return nil,"install failed; rollback failed: "..tostring(why)end
        return nil,err
    end
    removeTree(staging)
    return true
end
return Install
