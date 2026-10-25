local Home = {}
function Home.install(Engine,assign)
    local BB=require("ffi/blitbuffer")
    local Theme=require("ui.themes")
    local function walk(w,fn)
        fn(w);for _,child in ipairs(w)do if type(child)=="table"then walk(child,fn)end end
    end
    for _,entry in ipairs{
        {"desktop.pages.home.heatmap","home_heatmap"},
        {"desktop.pages.home.tiles","home_tiles"},
    }do
        local ok,mod=pcall(require,entry[1])
        Engine.coverage[entry[2]]=ok and type(mod.createWidget)=="function"
        if Engine.coverage[entry[2]]then
            local create=mod.createWidget
            local heatmap=entry[2]=="home_heatmap"
            assign(mod,"createWidget",function(self,...)
                local widget=create(self,...)
                if not Engine.active()or not Engine.config().statistics then return widget end
                local track=Theme.current().progress.track
                walk(widget,function(w)
                    local style=w.style
                    if type(style)~="table"then return end
                    if heatmap and w.keep_bg and type(style.bg)=="number" and style.bg<track then
                        style.bg=Engine.tint(0.22+0.78*(track-style.bg)/math.max(1,track),"stat1")
                    elseif not heatmap and style.bg==0 and not style.border_color and not style.border then
                        style.bg=Engine.accentToken((style.radius or 0)>100 and "stat2"or"stat1")
                    end
                end)
                return widget
            end)
        end
    end

    local ok,Ring=pcall(require,"ui.widgets.ring")
    Engine.coverage.rings=ok
    if not ok then return end
    local paint,free=Ring.paintTo,Ring.free
    local shared,order,bytes,shared_revision={},{},0,-1
    local function release(c)
        c.refs=c.refs-1
        if c.refs==0 and not c.cached then c.image:free()end
    end
    local function evict()
        local key=table.remove(order,1)
        local c=shared[key];shared[key]=nil;bytes=bytes-c.bytes;c.cached=false
        if c.refs==0 then c.image:free()end
    end
    local tables,lut_revision={},-1
    local function lut(role)
        if lut_revision~=Engine.revision then tables={};lut_revision=Engine.revision end
        if not tables[role]then
            local values={}
            for v=0,255 do values[v]=Engine.color(Engine.tint(1-v/255,role))end
            tables[role]=values
        end
        return tables[role]
    end
    local function draw(self,bb,x,y)
        local count=#self.rings
        local th=self.thickness or math.max(3,math.floor(self.size/(count*2+8)))
        local gap=math.max(3,math.floor(th/2))
        local center=math.floor(self.size/2)
        local radius=center-math.ceil(th/2)
        local bands={}
        for i=1,count do
            bands[i]={outer=(radius+th/2+1)^2,inner=math.max(0,radius-th/2-1)^2,colors=lut("stat"..((i-1)%3+1))}
            radius=radius-th-gap
        end
        local view={setPixel=function(_,px,py,c)
            local gray=type(c)=="number"and c or c:getColor8().a
            local distance=(px-x-center)^2+(py-y-center)^2
            for _,band in ipairs(bands)do
                if distance>=band.inner and distance<=band.outer then c=band.colors[gray];break end
            end
            return bb:setPixel(px,py,c)
        end}
        paint(self,view,x,y)
    end
    assign(Ring,"paintTo",function(self,bb,x,y)
        if not Engine.active()or not Engine.config().statistics then return paint(self,bb,x,y)end
        if shared_revision~=Engine.revision then
            while #order>0 do evict()end
            shared_revision=Engine.revision
        end
        local c=self._moon_color_ring
        local theme_id=Theme.id()
        local hit=c and c.theme_id==theme_id and c.size==self.size and c.thickness==self.thickness and c.revision==Engine.revision and #c.fractions==#self.rings
        if hit then for i,ring in ipairs(self.rings)do if c.fractions[i]~=(ring.fraction or 0)then hit=false;break end end end
        if not hit then
            if c and c.image then release(c)end
            self._moon_color_ring=nil
            if BB.new and BB.TYPE_BBRGB32 and bb.alphablitFrom and self.size<=512 then
                local parts={theme_id,self.size,self.thickness or 0}
                for _,ring in ipairs(self.rings)do parts[#parts+1]=ring.fraction or 0 end
                local key=table.concat(parts,":")
                c=shared[key]
                if c then
                    c.refs=c.refs+1;self._moon_color_ring=c;hit=true
                    for i,k in ipairs(order)do if k==key then table.remove(order,i);break end end
                    order[#order+1]=key
                else
                local good,image=pcall(BB.new,self.size,self.size,BB.TYPE_BBRGB32)
                if good then
                    image:paintRectRGB32(0,0,self.size,self.size,BB.ColorRGB32(255,255,255,0))
                    draw(self,image,0,0)
                    c={image=image,size=self.size,thickness=self.thickness,revision=Engine.revision,theme_id=theme_id,fractions={},
                        refs=1,cached=true,bytes=self.size*self.size*4}
                    for i,ring in ipairs(self.rings)do c.fractions[i]=ring.fraction or 0 end
                    self._moon_color_ring=c
                    hit=true
                    shared[key]=c;order[#order+1]=key;bytes=bytes+c.bytes
                    while #order>8 or bytes>4*1024*1024 do evict()end
                end
                end
            end
        end
        self.dimen.x,self.dimen.y=x,y
        if hit then return bb:alphablitFrom(c.image,x,y,0,0,self.size,self.size)end
        return draw(self,bb,x,y)
    end)
    assign(Ring,"free",function(self,...)
        local c=self._moon_color_ring
        if c and c.image then release(c);self._moon_color_ring=nil end
        if free then return free(self,...)end
    end)

    -- 首页底部翻页圆点：主题里当前页是黑点、其余是灰点，这里换成强调色。
    -- 结构固定为 [上一页按钮, CenterContainer[圆点行], 下一页按钮]，只在 dots 模式（首页）生效。
    local pager_ok,Pager=pcall(require,"ui.themes.widgets.pager")
    Engine.coverage.pager=pager_ok and type(Pager.widget)=="function"
    if Engine.coverage.pager then
        local widget=Pager.widget
        assign(Pager,"widget",function(opts)
            local pager=widget(opts)
            if type(opts)~="table" or not opts.dots or opts.center then return pager end
            if not Engine.active() or not Engine.config().tabs then return pager end
            local row=pager[2] and pager[2][1]
            if type(row)~="table" then return pager end
            local ink=Theme.current().color.ink
            local active,idle=Engine.accentToken("navigation"),Engine.tint(0.32,"navigation")
            for i=1,#row do
                local dot=row[i]
                local style=type(dot)=="table" and dot.style
                -- 圆点是边长相同的 Box；两侧的 HorizontalSpan 只有宽度，跳过。
                -- 主题色是数字（不是 BB 颜色对象），直接比数字；用真值判断避免和 nil 比较。
                if type(style)=="table" and style.bg and dot.width==dot.height then
                    style.bg=style.bg==ink and active or idle
                end
            end
            return pager
        end)
    end
end
return Home
