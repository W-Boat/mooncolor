-- Pure theme data and validation; independent of Moon/KOReader.
local Themes = {}
Themes.roles = {
    {id="primary", name="按钮"}, {id="icons", name="图标"}, {id="headings", name="标题与数字"},
    {id="navigation", name="导航"}, {id="progress", name="进度与角标"},
    {id="stat1", name="统计主色 / 外环"}, {id="stat2", name="统计第二色 / 中环"},
    {id="stat3", name="统计第三色 / 内环"}, {id="borders", name="卡片与弹窗边框"},
}
local function mono(hex)
    local out={};for _,role in ipairs(Themes.roles)do out[role.id]=hex end;return out
end
Themes.presets = {
    {id="ocean",name="深海蓝",rgb=0x205CA8,colors=mono("#205CA8")},
    {id="pine",name="松石绿",rgb=0x16685C,colors=mono("#16685C")},
    {id="clay",name="赤陶红",rgb=0xA34434,colors=mono("#A34434")},
    {id="aurora",name="极光 · 蓝绿橙",rgb=0x205CA8,colors={primary="#205CA8",icons="#16685C",headings="#604A96",
        navigation="#205CA8",progress="#16685C",stat1="#205CA8",stat2="#B45A24",stat3="#16685C",borders="#52677C"}},
    {id="garden",name="花园 · 绿紫红",rgb=0x246648,colors={primary="#246648",icons="#66509A",headings="#A34454",
        navigation="#246648",progress="#66509A",stat1="#246648",stat2="#66509A",stat3="#A34454",borders="#62705A"}},
    {id="sunset",name="日落 · 红蓝金",rgb=0xA34434,colors={primary="#A34434",icons="#285D88",headings="#865E20",
        navigation="#A34434",progress="#285D88",stat1="#A34434",stat2="#285D88",stat3="#865E20",borders="#795C54"}},
}
function Themes.hex(value)
    if type(value)~="string" then return nil end
    value=value:match("^%s*(.-)%s*$"):gsub("^#","")
    if #value==3 and value:match("^%x%x%x$")then value=value:gsub("(.)","%1%1")end
    if #value~=6 or not value:match("^%x+$")then return nil end
    return "#"..value:upper()
end
function Themes.rgb(hex)return tonumber(hex:sub(2),16)end
function Themes.find(id)
    for _,p in ipairs(Themes.presets)do if p.id==id then return p end end
end
function Themes.resolve(id, custom)
    local p=Themes.find(id)or Themes.presets[1]
    local out={}
    for _,r in ipairs(Themes.roles)do out[r.id]=(id=="custom" and type(custom)=="table" and Themes.hex(custom[r.id]))or p.colors[r.id]end
    return out
end
function Themes.foreground(rgb)
    local function lin(n)n=n/255;return n<=0.04045 and n/12.92 or ((n+0.055)/1.055)^2.4 end
    local lum=0.2126*lin(math.floor(rgb/65536))+0.7152*lin(math.floor(rgb/256)%256)+0.0722*lin(rgb%256)
    return (lum+0.05)/0.05 >= 1.05/(lum+0.05) and 0 or 255
end
return Themes
