-- Navigation layout only. All colors are supplied/rendered by Moon's theme.
local Nav={}
function Nav.install(Engine,assign)
    local Theme=require("ui.themes")
    local Tabbar=require("ui.themes.widgets.tabbar")
    local Box=require("ui.themes.widgets.box")
    local Icon=require("ui.themes.widgets.icon")
    local Text=require("ui.themes.widgets.text")
    local Tap=require("ui.themes.widgets.tap")
    local Center=require("ui/widget/container/centercontainer")
    local Geom=require("ui/geometry")
    local HG=require("ui/widget/horizontalgroup")
    local VG=require("ui/widget/verticalgroup")
    local Span=require("ui/widget/verticalspan")
    local GestureRange=require("ui/gesturerange")
    local color=Theme.color or require("ffi/blitbuffer").Color8
    local height,widget=Tabbar.height,Tabbar.widget
    local context="navbar"
    local function options()
        local c=Engine.config()
        return c[context.."_labels"],c[context.."_style"],c[context.."_compact"]
    end
    -- Scope only the public sidebar render call. Never load the sidebar eagerly,
    -- inspect private upvalues or let its dimensions affect the desktop.
    local wrapped=setmetatable({},{__mode="k"})
    Engine.attachSidebar=function()
        local sidebar=package.loaded["features.sidebar"]
        if type(sidebar)~="table"or type(sidebar.render)~="function"or wrapped[sidebar]then return end
        local render=sidebar.render
        assign(sidebar,"render",function(self,...)
            if not Engine.config().enabled then return render(self,...)end
            local previous=context;context="sidebar"
            local result={pcall(render,self,...)};context=previous
            if not result[1]then error(result[2],0)end
            return unpack(result,2)
        end)
        wrapped[sidebar]=true
    end
    Engine.attachSidebar()
    assert(type(height)=="function"and type(widget)=="function","月读底栏接口不兼容")
    assign(Tabbar,"height",function()
        if not Engine.installed or not Engine.config().enabled then return height()end
        local labels,_,compact=options()
        return Theme.px(labels and(compact and 56 or 64)or(compact and 40 or 48))
    end)
    assign(Tabbar,"widget",function(opts)
        if not Engine.installed or not Engine.config().enabled then return widget(opts)end
        local conf,t=Engine.config(),Theme.current()
        local h=opts.height or Tabbar.height()
        local rule=math.max(1,Theme.px(t.row.divider))
        local cell_h=math.max(1,h-rule)
        local row=HG:new{align="top"}
        local show_labels,style,compact=options()
        local labels=show_labels and opts.show_labels~=false
        local accent=t.color.navigation or t.color.ink
        local fill=Theme.mix and Theme.mix(t.color.page,accent,.16)or 0xEE
        for i,tab in ipairs(opts.tabs)do
            local current=tab
            local active=current.id==opts.active
            local width=math.floor(i*opts.width/#opts.tabs)-math.floor((i-1)*opts.width/#opts.tabs)
            local badge_w=math.max(1,math.min(Theme.px(64),width-Theme.px(8)))
            local badge_h=math.min(Theme.px(32),cell_h)
            local ink=active and accent or(opts.plain and t.color.ink or t.color.faint)
            local pill=active and style=="pill"
            local stack=VG:new{align="center",Box:new{
                style={bg=pill and fill or nil,border=pill and 1 or 0,
                    border_color=accent,radius=pill and 999 or 0},
                width=badge_w,height=badge_h,
                Icon.widget{name=current.icon,size=math.min(t.control.icon+(compact and 0 or 2),28),color=color(ink)},
            }}
            if labels then
                stack[#stack+1]=Span:new{width=Theme.px(3)}
                stack[#stack+1]=Text.line("caption",current.text,{
                    width=math.max(1,width-Theme.px(6)),bold=active,color=ink})
            end
            if active and style=="line"then
                stack[#stack+1]=Span:new{width=Theme.px(3)}
                stack[#stack+1]=Box:new{style={bg=accent},keep_bg=true,
                    width=math.min(badge_w,Theme.px(28)),height=Theme.px(3)}
            end
            local tap
            tap=Tap.wrap(Center:new{dimen=Geom:new{w=width,h=cell_h},stack},function()
                if not active and opts.on_tab then opts.on_tab(current.id,tap.dimen)end
            end)
            if not labels then
                tap.ges_events.MoonNavHold={
                    GestureRange:new{ges="hold",range=function()return tap.dimen end},args=tap}
                function tap:onMoonNavHold(owner)
                    if owner and owner~=self then return end
                    require("ui.themes.widgets.toast"):new{text=current.text}:show()
                    return true
                end
            end
            row[#row+1]=tap
        end
        return VG:new{align="left",
            Box:new{style={bg=t.color.rule},width=opts.width,height=rule},row}
    end)
    Engine.coverage.navbar=true
end
return Nav
