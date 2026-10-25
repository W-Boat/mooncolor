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
        local c=self._moon_color_ring
        local theme_id=Theme.id()
        local hit=c and c.theme_id==theme_id and c.size==self.size and c.thickness==self.thickness and c.revision==Engine.revision and #c.fractions==#self.rings
        if hit then for i,ring in ipairs(self.rings)do if c.fractions[i]~=(ring.fraction or 0)then hit=false;break end end end
        if not hit then
            if c and c.image then c.image:free()end
            self._moon_color_ring=nil
            if BB.new and BB.TYPE_BBRGB32 and bb.alphablitFrom and self.size<=512 then
                local good,image=pcall(BB.new,self.size,self.size,BB.TYPE_BBRGB32)
                if good then
                    image:paintRectRGB32(0,0,self.size,self.size,BB.ColorRGB32(255,255,255,0))
                    draw(self,image,0,0)
                    c={image=image,size=self.size,thickness=self.thickness,revision=Engine.revision,theme_id=theme_id,fractions={}}
                    for i,ring in ipairs(self.rings)do c.fractions[i]=ring.fraction or 0 end
                    self._moon_color_ring=c
                    hit=true
                end
            end
        end
        self.dimen.x,self.dimen.y=x,y
        if hit then return bb:alphablitFrom(c.image,x,y,0,0,self.size,self.size)end
        return draw(self,bb,x,y)
    end)
    assign(Ring,"free",function(self,...)
        local c=self._moon_color_ring
        if c and c.image then c.image:free();self._moon_color_ring=nil end
        if free then return free(self,...)end
    end)
end
return Home
