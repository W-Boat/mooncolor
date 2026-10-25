-- Reuse Moon's asynchronous HTTP transport, timeout policy and themed UI.
local Update={busy=false,REPO="W-Boat/mooncolor"}
function Update.newer(candidate,installed)
    local a,b={candidate:match("^v?(%d+)%.(%d+)%.(%d+)$")},{installed:match("^(%d+)%.(%d+)%.(%d+)$")}
    if #a~=3 or #b~=3 then return false end
    for i=1,3 do if tonumber(a[i])~=tonumber(b[i])then return tonumber(a[i])>tonumber(b[i])end end
    return false
end
function Update.parse(body)
    local ok,data=pcall(require("json").decode,body)
    if not ok or type(data)~="table"or data.draft or data.prerelease then return nil,"无效的更新响应"end
    local tag=type(data.tag_name)=="string"and data.tag_name:match("^v?(%d+%.%d+%.%d+)$")
    if not tag then return nil,"未找到稳定版本"end
    local expected="https://github.com/"..Update.REPO.."/releases/tag/v"..tag
    return {version=tag,url=expected,notes=type(data.body)=="string"and data.body or""}
end
local function notice(text)
    require("ui.themes.widgets.toast"):new{text=text,timeout=4}:show()
end
function Update.check()
    if Update.busy then notice("正在检查更新…");return end
    Update.busy=true
    notice("正在检查 Moon Color 更新…")
    local ok,err=pcall(function()
        require("http.request").get("https://api.github.com/repos/"..Update.REPO.."/releases/latest",{
            timeout=require("http.timeout").net(1),
            headers={Accept="application/vnd.github+json",["X-GitHub-Api-Version"]="2022-11-28"},
        },function(body,err)
            Update.busy=false
            if err then notice("检查失败："..tostring(err));return end
            local release,reason=Update.parse(body)
            if not release then notice(reason);return end
            local version=require("mooncolor_engine").VERSION
            if not Update.newer(release.version,version)then notice("已是最新版本 · "..version);return end
            require("ui.themes.widgets.sheet"):new{title="Moon Color "..release.version,items={
                {text="查看更新并下载（二维码）",callback=function()
                    require("ui.themes.widgets.qr"):new{title="Moon Color "..release.version,text=release.url,
                        caption="扫码下载安装包，覆盖插件后重启 KOReader"}:show()
                end},
                {text="更新说明",callback=function()
                    require("ui.themes.widgets.text_viewer"):new{title="更新说明",text=release.notes}:show()
                end},
            }}:show()
        end)
    end)
    if not ok then Update.busy=false;notice("检查失败："..tostring(err))end
end
return Update
