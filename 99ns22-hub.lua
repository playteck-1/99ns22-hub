-- ModVip - Steal An Egg: SPAWNER VISUAL (so aparece na SUA tela, nao e real)
-- Pets: ReplicatedStorage.AssetModels | Ovos: copia de ovos do mapa (AreaEggSlotsClient)
-- Modos: Base (dentro do seu plot) | Fixo (onde voce clicou) | Seguir (atras de voce)
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LP         = Players.LocalPlayer

if getgenv and getgenv().ModVipVisual then pcall(function() getgenv().ModVipVisual:Destroy() end) end

-- mata versoes antigas: apaga os pets delas e marca uma sessao nova
local SESSION = tick()
if getgenv then getgenv().ModVipVisualSession = SESSION end
local function alive() return not getgenv or getgenv().ModVipVisualSession == SESSION end

local folder = workspace:FindFirstChild("ModVipVisuals") or Instance.new("Folder")
folder.Name = "ModVipVisuals"; folder.Parent = workspace
folder:ClearAllChildren()

local spawned = {}      -- {model, size, centerToPivot}
local GK                -- o que aprendemos do jogo (preenchido mais abaixo)
local mode = "Base"     -- "Base", "Fixo", "Seguir"
local scale = 1
local fixedAnchor, fixedFeetY
local GAP = 3

local function root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- ================= ACHAR MEU PLOT =================
local mySlot
pcall(function()
    RS.Packages.Networking["RE/Homestead/StateShifted"].OnClientEvent:Connect(function(d)
        if type(d) == "table" and d.UserId == LP.UserId and d.Slot then mySlot = d.Slot end
    end)
end)

local function findSlotIn(t, depth)
    if type(t) ~= "table" or depth > 4 then return end
    if (t.UserId == LP.UserId or t.OwnerUserId == LP.UserId) and t.Slot then return t.Slot end
    if t[LP.UserId] and type(t[LP.UserId]) == "table" and t[LP.UserId].Slot then return t[LP.UserId].Slot end
    for _, v in pairs(t) do
        local s = findSlotIn(v, depth + 1)
        if s then return s end
    end
end

task.spawn(function()
    pcall(function()
        local st = RS.Packages.Networking["RF/Homestead/AskState"]:InvokeServer()
        mySlot = mySlot or findSlotIn(st, 0)
    end)
end)

local function nearestPlot(pos)
    local plots = workspace:FindFirstChild("Plots"); if not plots then return end
    local best, bd
    for _, p in ipairs(plots:GetChildren()) do
        local c = p:FindFirstChild("CenterPoint")
        if c then
            local d = (c.Position - pos).Magnitude
            if not bd or d < bd then best, bd = p, d end
        end
    end
    return best, bd
end

-- placa com meu nome (BillboardGui "PlayerPlotSign" pode estar no PlayerGui ou no plot)
local function plotBySign()
    local roots = {workspace:FindFirstChild("Plots"), LP:FindFirstChild("PlayerGui")}
    for _, rt in ipairs(roots) do
        if rt then
            for _, g in ipairs(rt:GetDescendants()) do
                if g:IsA("BillboardGui") or g:IsA("SurfaceGui") then
                    for _, t in ipairs(g:GetDescendants()) do
                        if (t:IsA("TextLabel") or t:IsA("TextButton")) and t.Text ~= ""
                            and (t.Text:find(LP.Name, 1, true) or t.Text:find(LP.DisplayName, 1, true)) then
                            local part = g.Adornee or g.Parent
                            if part and part:IsA("BasePart") then
                                local p, d = nearestPlot(part.Position)
                                if p and d < 80 then return p end
                            end
                        end
                    end
                end
            end
        end
    end
end

local lastPlotScan = 0
local function myPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    if mySlot and plots:FindFirstChild(tostring(mySlot)) then return plots[tostring(mySlot)] end
    -- busca pesada (placas/renders): no maximo 1x a cada 5s se nao achar
    if tick() - lastPlotScan < 5 then return end
    lastPlotScan = tick()
    local s = plotBySign()
    if s then mySlot = s.Name return s end
    -- plano B: meus ovos/pets renderizados (nome comeca com meu UserId)
    local prefix = tostring(LP.UserId) .. "_"
    for _, fname in ipairs({"ClientRenderedAssets", "PlacedEggRenders"}) do
        local f = workspace:FindFirstChild(fname)
        if f then
            for _, m in ipairs(f:GetChildren()) do
                if m.Name:sub(1, #prefix) == prefix and m:IsA("Model") then
                    local pos = m:GetPivot().Position
                    local best, bd
                    for _, p in ipairs(plots:GetChildren()) do
                        local c = p:FindFirstChild("CenterPoint")
                        if c then
                            local d = (c.Position - pos).Magnitude
                            if not bd or d < bd then best, bd = p, d end
                        end
                    end
                    if best and bd < 130 then mySlot = tonumber(best.Name) or best.Name; return best end
                end
            end
        end
    end
end

-- ancora do cercado: comeca no centro do plot e cresce pro lado oposto ao spawn
local function baseAnchor()
    local p = myPlot(); if not p then return end
    local c, s = p:FindFirstChild("CenterPoint"), p:FindFirstChild("SpawnPoint")
    if not c then return end
    local dir = s and (c.Position - s.Position) or Vector3.new(-1, 0, 0)
    dir = Vector3.new(dir.X, 0, dir.Z)
    if dir.Magnitude < 0.1 then dir = Vector3.new(-1, 0, 0) end
    dir = dir.Unit
    local start = c.Position + dir * 6
    -- olhando PARA o spawn => +Z local aponta pra dentro do cercado
    return CFrame.lookAt(start, start - dir), c.Position.Y - 0.5
end

-- ================= MODELOS =================
-- O jogo cria na hora as juntas (Motor6D "<peca>Motor6D") ligando cada peca do pet ao RootPart.
-- Os modelos guardados vem SEM elas: sem juntas a animacao toca mas nada mexe (asas paradas).
local function rigLikeGame(m)
    local inner = m:FindFirstChild("Model")
    if not (inner and inner:IsA("Model")) then inner = m end
    local root = inner:FindFirstChild("RootPart")
    if not (root and root:IsA("BasePart")) then return 0 end
    local hasMotor = {}
    for _, j in ipairs(m:GetDescendants()) do
        if j:IsA("Motor6D") and j.Part1 then hasMotor[j.Part1] = true end
    end
    -- tira as colas das pecas do pet (elas travavam asas/cauda no lugar)
    for _, j in ipairs(inner:GetDescendants()) do
        if (j:IsA("Weld") or j:IsA("WeldConstraint") or j:IsA("ManualWeld")) and j.Part0 and j.Part1
            and j.Part0:IsDescendantOf(inner) and j.Part1:IsDescendantOf(inner) then
            j:Destroy()
        end
    end
    local n = 0
    for _, part in ipairs(inner:GetDescendants()) do
        if part:IsA("BasePart") and part ~= root and not hasMotor[part] then
            local j = Instance.new("Motor6D")
            j.Name = part.Name .. "Motor6D"
            j.Part0, j.Part1 = root, part
            j.C0 = root.CFrame:Inverse() * part.CFrame
            j.Parent = part
            n = n + 1
        end
    end
    m:SetAttribute("MV_Rigged", n)
    return n
end

local function prep(m)
    rigLikeGame(m)
    -- partes presas por junta ficam soltas (a animacao mexe nelas); o resto fica travado
    local jointed = {}
    for _, j in ipairs(m:GetDescendants()) do
        if (j:IsA("JointInstance") or j:IsA("WeldConstraint")) and j.Part1 then jointed[j.Part1] = true end
    end
    local inner = m:FindFirstChild("Model")
    local rootPart = (inner and inner:FindFirstChild("RootPart")) or m:FindFirstChild("RootPart")
    if rootPart then jointed[rootPart] = nil end
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") then
            p.Anchored = not jointed[p]
            p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
            p.Massless = true
        elseif p:IsA("Script") or p:IsA("LocalScript") then
            p:Destroy()
        end
    end
    local hide = {HumanoidRootPart = true, CenterCFrame = true, CENTER = true, Hitbox = true, CustomBoundingBox = true, RootPart = true}
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") and hide[p.Name] then p.Transparency = 1 end
    end
end

-- ================= ANIMACAO =================
local function toAnimId(v)
    if type(v) == "number" and v > 1000 then return "rbxassetid://" .. v end
    if type(v) == "string" then
        local n = v:match("rbxassetid://(%d+)") or v:match("^(%d%d%d%d%d+)$") or v:match("id=(%d+)")
        if n then return "rbxassetid://" .. n end
    end
end

-- procura IDs de animacao na config do pet (prefere idle)
local function animIdsFromConfig(name)
    local found = {}
    pcall(function()
        local mod = RS.Data.Assets.Configs:FindFirstChild(name)
        if not mod then return end
        local cfg = require(mod)
        local seen = {}
        local function scan(t, path, depth)
            if type(t) ~= "table" or depth > 5 or seen[t] then return end
            seen[t] = true
            for k, v in pairs(t) do
                local key = path .. "/" .. tostring(k)
                if type(v) == "table" then
                    scan(v, key, depth + 1)
                elseif typeof(v) == "Instance" and v:IsA("Animation") then
                    table.insert(found, {key = key:lower(), id = v.AnimationId})
                else
                    local id = toAnimId(v)
                    local lk = key:lower()
                    if id and (lk:find("anim") or lk:find("idle") or lk:find("walk") or lk:find("move")) then
                        table.insert(found, {key = lk, id = id})
                    end
                end
            end
        end
        scan(cfg, "", 0)
    end)
    local function rank(k) return k:find("idle") and 0 or (k:find("walk") and 1 or 2) end
    table.sort(found, function(a, b) return rank(a.key) < rank(b.key) end)
    return found
end

-- "Alien Skeleton Boss" / "AlienSkeletonBossV2" / "<b>Alien Skeleton Boss</b>" -> "alienskeletonboss"
local function norm(s)
    s = tostring(s or ""):gsub("<[^>]->", ""):lower():gsub("[^%w]", "")
    s = s:gsub("v%d+$", "")
    return s
end

local function namesMatch(a, b)
    if a == "" or b == "" then return false end
    return a == b or (#a >= 5 and #b >= 5 and (a:find(b, 1, true) or b:find(a, 1, true)))
end

-- textos da placa "Data" em cima do pet real (mostra o nome do pet)
local function realPetTags(pm)
    local tags = {}
    for _, k in ipairs({"ReviewCategory", "PreparedSourceName", "AssetCategory", "AssetName"}) do
        local v = pm:GetAttribute(k)
        if v then table.insert(tags, norm(tostring(v):match("([^%.]+)$"))) end
    end
    local data = pm:FindFirstChild("Data")
    if data then
        for _, t in ipairs(data:GetDescendants()) do
            if t:IsA("TextLabel") and t.Text ~= "" then table.insert(tags, norm(t.Text)) end
        end
    end
    local inner = pm:FindFirstChild("Model")
    if inner then table.insert(tags, norm(inner:GetAttribute("AssetName") or "")) end
    return tags
end

local function tracksOf(pm, out)
    for _, an in ipairs(pm:GetDescendants()) do
        if an:IsA("Animator") then
            for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
                if tr.Animation and tr.Animation.AnimationId ~= "" then
                    table.insert(out, {key = "live/" .. tr.Name:lower(), id = tr.Animation.AnimationId})
                end
            end
        end
    end
end

-- pega a animacao que o PROPRIO JOGO esta tocando num pet real do mesmo tipo (nas bases)
local function liveAnimIds(name)
    local out, want = {}, norm(name)
    local f = workspace:FindFirstChild("ClientRenderedAssets")
    if not f then return out end
    for _, pm in ipairs(f:GetChildren()) do
        local hit = false
        local data = pm:FindFirstChild("Data")
        local dn = data and data:FindFirstChild("DisplayName")
        if GK and GK.baseName and GK.baseName(pm, dn and (dn.Text:gsub("<[^>]->", "")) or nil) == name then hit = true end
        if not hit then
            for _, tag in ipairs(realPetTags(pm)) do
                if tag == want then hit = true break end      -- nome EXATO (antes pegava pets parecidos)
            end
        end
        if hit then
            tracksOf(pm, out)
            if #out > 0 then return out end
        end
    end
    return out
end

-- objetos Animation espalhados no jogo cujo nome/pasta tem o nome do pet
local animIndex          -- fica pronto em segundo plano (ver warmup no fim do arquivo)
local animIndexBuilding = false
local function buildAnimIndexAsync()
    if animIndex or animIndexBuilding then return end
    animIndexBuilding = true
    local idx = {}
    local all = RS:GetDescendants()
    for i, a in ipairs(all) do
        if a:IsA("Animation") and a.AnimationId ~= "" then
            local chain, p = {}, a
            for _ = 1, 4 do
                if not p or p == game then break end
                table.insert(chain, norm(p.Name)); p = p.Parent
            end
            table.insert(idx, {chain = chain, id = a.AnimationId, key = a.Name:lower()})
        end
        if i % 3000 == 0 then task.wait() end     -- pausa: nao trava o jogo
    end
    animIndex = idx
    animIndexBuilding = false
end
local function indexedAnimIds(name)
    if not animIndex then task.spawn(buildAnimIndexAsync) return {} end   -- ainda carregando: nao espera
    local out, want = {}, norm(name)
    for _, e in ipairs(animIndex) do
        for _, c in ipairs(e.chain) do
            if namesMatch(c, want) then table.insert(out, {key = "idx/" .. e.key, id = e.id}) break end
        end
    end
    return out
end

local animDebug = {}

local function playAnim(m, name, s)
    local ac = m:FindFirstChildWhichIsA("AnimationController", true) or m:FindFirstChildWhichIsA("Humanoid", true)
    local dbg = {pet = name, controller = ac and ac.ClassName or "NENHUM", config = 0, index = 0}
    animDebug[#animDebug + 1] = dbg
    if not ac then return false end
    local animator = ac:FindFirstChildOfClass("Animator") or Instance.new("Animator", ac)
    -- 1) memoria (o que pets reais desse tipo tocaram parado/andando)  2) pet real igual no servidor agora
    local mem = GK and GK.info and GK.info[name] and GK.info[name].anims
    local live = liveAnimIds(name)
    dbg.live = #live
    local info = GK and GK.info and GK.info[name]
    if info and info.rig then dbg.rig = (GK.rigSig(m) == info.rig) and "igual ao jogo" or "diferente do jogo" end
    local idle = (mem and (mem.idle or mem.walk)) or (live[1] and live[1].id)
    local walk = (mem and mem.walk) or idle
    dbg.total = idle and 1 or 0
    if not idle then dbg.err = "nenhum pet real desse tipo visto ainda (aprende sozinho quando aparecer um)" return false end
    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
    local function load(id)
        local a = Instance.new("Animation")
        a.AnimationId = id
        local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
        if ok and tr then tr.Looped = true return tr end
    end
    local ti = load(idle)
    if not ti then dbg.err = "LoadAnimation falhou" return false end
    local tw = (walk ~= idle) and load(walk) or nil
    ti:Play(0.2)
    if s then s.trIdle, s.trWalk, s.wasMoving = ti, tw, false end
    dbg.played = idle .. (tw and (" / andando " .. walk) or "")
    return true
end

-- caixa so das partes VISIVEIS (ignora pecas tecnicas invisiveis longe do pet)
local function visualBox(m)
    local mn, mx
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 1 then
            local h = p.Size / 2
            local a, b = p.Position - h, p.Position + h
            mn = mn and Vector3.new(math.min(mn.X, a.X), math.min(mn.Y, a.Y), math.min(mn.Z, a.Z)) or a
            mx = mx and Vector3.new(math.max(mx.X, b.X), math.max(mx.Y, b.Y), math.max(mx.Z, b.Z)) or b
        end
    end
    if not mn then local cf, s = m:GetBoundingBox() return cf.Position, s end
    return (mn + mx) / 2, mx - mn
end

-- calcula a "casa" de cada pet em fileiras a partir da ancora (+Z local)
local function layoutFrom(anchor, feetY, maxRow)
    local rot = anchor - anchor.Position
    local back = 0
    local i = 1
    while i <= #spawned do
        local row, width, depth = {}, 0, 0
        while i <= #spawned do
            local s = spawned[i]
            local w = width + (#row > 0 and GAP or 0) + s.size.X
            if #row > 0 and w > maxRow then break end
            table.insert(row, s); width = w; depth = math.max(depth, s.size.Z)
            i = i + 1
        end
        local x = -width / 2
        local z = back + depth / 2
        for _, s in ipairs(row) do
            local p = (anchor * CFrame.new(x + s.size.X / 2, 0, z)).Position
            s.home = CFrame.new(p.X, feetY + s.size.Y / 2, p.Z) * rot
            s.slotW = s.size.X + GAP
            s.goal = nil
            if not s.pos then s.pos = s.home end
            x = x + s.size.X + GAP
        end
        back = back + depth + GAP
    end
end

local statusLabel
local function setStatus(t) if statusLabel then statusLabel.Text = t end end

-- mede o modelo na escala atual e guarda tamanho/relacao centro->pivot
local function measure(s)
    local center, size = visualBox(s.model)
    local pivot = s.model:GetPivot()
    local centerCF = CFrame.new(center) * (pivot - pivot.Position)
    local foot = math.max(size.X, size.Z)
    s.size = Vector3.new(foot, size.Y, foot)
    s.centerToPivot = centerCF:Inverse() * pivot
end

local function rescale(s, k)
    if s.k and math.abs(s.k - k) < 0.01 then return end
    pcall(function() s.model:ScaleTo(k) end)
    s.k = k
    measure(s)
end

-- sistema de coordenadas do plot: -Z olha pro spawn, +Z vai pro fundo do cercado
local function plotFrame(p)
    local c, sp = p:FindFirstChild("CenterPoint"), p:FindFirstChild("SpawnPoint")
    if not c then return end
    local s = sp and Vector3.new(sp.Position.X, c.Position.Y, sp.Position.Z) or (c.Position + Vector3.new(1, 0, 0))
    if (s - c.Position).Magnitude < 0.1 then s = c.Position + Vector3.new(1, 0, 0) end
    return CFrame.lookAt(c.Position, s)
end

-- area do cercado: medida pelo modelo da base (ToUpdate); se falhar usa o tamanho padrao
local function penArea(p, frame)
    local x0, x1, z0, z1 = -22, 22, -12, 88
    local base = p:FindFirstChild("ToUpdate")
    -- o proprio jogo marca o chao do cercado: ToUpdate.PetArea (onde os pets reais andam)
    local pa = base and base:FindFirstChild("PetArea", true)
    if pa and pa:IsA("BasePart") then
        local mnX, mxX, mnZ, mxZ
        for _, sx in ipairs({-1, 1}) do
            for _, sz in ipairs({-1, 1}) do
                local l = frame:PointToObjectSpace((pa.CFrame * CFrame.new(sx * pa.Size.X / 2, 0, sz * pa.Size.Z / 2)).Position)
                mnX = math.min(mnX or l.X, l.X); mxX = math.max(mxX or l.X, l.X)
                mnZ = math.min(mnZ or l.Z, l.Z); mxZ = math.max(mxZ or l.Z, l.Z)
            end
        end
        if (mxX - mnX) > 10 and (mxZ - mnZ) > 10 then
            return mnX + 2, mxX - 2, mnZ + 2, mxZ - 2, pa.Position.Y + pa.Size.Y / 2
        end
    end
    if base then
        local mnX, mxX, mnZ, mxZ
        for _, part in ipairs(base:GetDescendants()) do
            if part:IsA("BasePart") and part.Size.Magnitude < 400 then
                local l = frame:PointToObjectSpace(part.Position)
                mnX = math.min(mnX or l.X, l.X); mxX = math.max(mxX or l.X, l.X)
                mnZ = math.min(mnZ or l.Z, l.Z); mxZ = math.max(mxZ or l.Z, l.Z)
            end
        end
        if mnX and (mxX - mnX) > 20 and (mxZ - mnZ) > 20 then
            x0, x1 = mnX + 4, mxX - 4
            z0, z1 = math.max(mnZ + 4, -14), mxZ - 4
        end
    end
    return x0, x1, z0, z1
end

local penBox      -- cercado medido (os pets passeiam por ele todo)
-- coloca os pets em grade dentro do cercado (tamanho = o escolhido no menu)
local function layoutBase()
    local p = myPlot(); if not p then return false end
    local frame = plotFrame(p); if not frame then return false end
    local x0, x1, z0, z1, floorY = penArea(p, frame)
    local W, D, n = x1 - x0, z1 - z0, #spawned
    local biggest = 0
    for _, s in ipairs(spawned) do biggest = math.max(biggest, (s.origFoot or 8) * scale) end
    local f = math.max(8, biggest)   -- espaco de cada pet = maior pet (nunca encolhe sozinho)
    local cols = math.max(1, math.floor((W + GAP) / (f + GAP)))
    local feetY = floorY or (frame.Position.Y - 0.5)
    penBox = {frame = frame, x0 = x0, x1 = x1, z0 = z0, z1 = z1}
    local rot = frame - frame.Position
    for i, s in ipairs(spawned) do
        rescale(s, scale)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local x = x0 + (col + 0.5) * (W / cols)
        local z = z0 + row * (f + GAP) + f / 2
        local wp = frame:PointToWorldSpace(Vector3.new(x, 0, z))
        s.home = CFrame.new(wp.X, feetY + s.size.Y / 2, wp.Z) * rot
        s.slotW = f + GAP
        s.goal = nil
        if not s.pos then s.pos = s.home end
    end
    return true
end

local function layout()
    if #spawned == 0 then return end
    if mode ~= "Base" then
        for _, s in ipairs(spawned) do rescale(s, scale) end
    end
    if mode == "Base" then
        if layoutBase() then return end
        setStatus("Base nao achada: va ate ela e clique 'Minha base e aqui'")
        if not fixedAnchor then
            local r = root()
            if r then
                local _, yaw = r.CFrame:ToEulerAnglesYXZ()
                fixedAnchor = CFrame.new(r.Position) * CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.new(0, 0, 4)
                fixedFeetY = r.Position.Y - 3
            end
        end
        if fixedAnchor then layoutFrom(fixedAnchor, fixedFeetY, 40) end
        return
    end
    if mode == "Fixo" and fixedAnchor then
        layoutFrom(fixedAnchor, fixedFeetY, 40)
        return
    end
    local r = root(); if not r then return end
    local _, yaw = r.CFrame:ToEulerAnglesYXZ()
    local anchor = CFrame.new(r.Position) * CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.new(0, 0, 4)
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    local feetY = r.Position.Y - r.Size.Y / 2 - (hum and hum.HipHeight or 2)
    layoutFrom(anchor, feetY, 30)
end

local wander = true   -- passear pelo cercado

local function spawnModel(src, label)
    local cached = GK and GK.renderCache and GK.renderCache[label]
    if cached then src = cached
    elseif GK and GK.petSource then src = GK.petSource(label) or src end
    local ok, m = pcall(function() return src:Clone() end)
    if not ok or not m then return false end
    if not m:IsA("Model") then local w = Instance.new("Model"); m.Parent = w; m = w end
    prep(m)
    m.Name = "Visual_" .. label
    m.Parent = folder
    local s = {model = m, phase = math.random() * 10, nextGoal = 0, petName = label, fromRender = cached ~= nil}
    pcall(function() s.k = m:GetScale() end)
    s.k = s.k or 1
    measure(s)
    s.origFoot = math.max(0.5, s.size.X / s.k)   -- tamanho na escala 1
    table.insert(spawned, s)
    layout()
    if s.home then s.model:PivotTo(s.home * s.centerToPivot) end
    s.animated = playAnim(m, label, s)
    return true, s
end

-- loop de movimento (~30 fps): passeia perto da casa + leve pulinho se nao tiver animacao
local lastCF, acc = nil, 0
local hb
hb = RunService.Heartbeat:Connect(function(dt)
    if not alive() then hb:Disconnect() return end
    if #spawned == 0 then return end
    acc = acc + dt
    if acc < 1 / 30 then return end
    local step = acc; acc = 0

    if mode == "Seguir" then
        local r = root()
        if r and (not lastCF or (r.Position - lastCF.Position).Magnitude > 0.3 or r.CFrame.LookVector:Dot(lastCF.LookVector) < 0.995) then
            lastCF = r.CFrame
            layout()
        end
    end

    local now = tick()
    local roam = wander and mode ~= "Seguir"
    for i = #spawned, 1, -1 do
        local s = spawned[i]
        if not s.model.Parent then
            table.remove(spawned, i)
        elseif s.home and not s.flying and not s.carried then
            if roam and not s.still and now > s.nextGoal then
                if mode == "Base" and penBox then
                    -- anda ate um ponto qualquer do cercado, para um pouco e escolhe outro (como os pets reais)
                    local W, D = penBox.x1 - penBox.x0, penBox.z1 - penBox.z0
                    local mx, mz = math.min(s.size.X / 2, W / 2), math.min(s.size.Z / 2, D / 2)
                    local lx = penBox.x0 + mx + math.random() * math.max(0, W - 2 * mx)
                    local lz = penBox.z0 + mz + math.random() * math.max(0, D - 2 * mz)
                    local wp = penBox.frame:PointToWorldSpace(Vector3.new(lx, 0, lz))
                    s.goal = CFrame.new(wp.X, s.home.Y, wp.Z) * (s.home - s.home.Position)
                    local far = s.pos and (s.goal.Position - s.pos.Position).Magnitude or 0
                    s.nextGoal = now + far / 6 + 2 + math.random() * 4
                else
                    local rad = math.max(1.5, s.slotW * 0.35)
                    s.goal = s.home * CFrame.new((math.random() * 2 - 1) * rad, 0, (math.random() * 2 - 1) * rad)
                    s.nextGoal = now + 2 + math.random() * 4
                end
            end
            local goal = (roam and not s.still and s.goal) or s.home
            local cur = s.pos or goal
            local delta = goal.Position - cur.Position
            local dist = delta.Magnitude
            local newPos, look = goal.Position, nil
            if dist > 120 and mode ~= "Seguir" then
                newPos = goal.Position   -- longe demais: aparece direto
            elseif dist > 0.05 then
                local spd = (mode == "Seguir") and math.max(16, dist * 4) or 6   -- studs/s
                newPos = cur.Position + delta.Unit * math.min(dist, spd * step)
                look = Vector3.new(delta.X, 0, delta.Z)
            end
            local curRot = cur - cur.Position
            local rot = curRot
            if look and look.Magnitude > 0.05 then
                rot = curRot:Lerp(CFrame.lookAt(Vector3.zero, look.Unit), math.min(1, step * 6))
            end
            s.pos = CFrame.new(newPos) * rot
            -- parado = animacao parada do pet real; andando = a de andar
            if s.trWalk then
                local mv = look ~= nil
                if mv ~= s.wasMoving then
                    s.wasMoving = mv
                    if mv then s.trIdle:Stop(0.25); s.trWalk:Play(0.25) else s.trWalk:Stop(0.25); s.trIdle:Play(0.25) end
                end
            end
            local bob = s.animated and 0 or math.abs(math.sin((now + s.phase) * 3)) * 0.4
            s.model:PivotTo(CFrame.new(0, bob, 0) * s.pos * s.centerToPivot)
        end
    end
end)

-- ================= BASE / ESTEIRA MAXIMA (VISUAL) =================
-- Copia a base de nivel mais alto do servidor (e a esteira de outro jogador) pro seu plot.
-- As suas originais ficam invisiveis SO na sua tela.
local HIDE_ATTR = "MV_OrigT"

-- restaura o que versoes antigas esconderam
for _, d in ipairs(workspace:GetDescendants()) do
    local t = d:GetAttribute(HIDE_ATTR)
    if t ~= nil then
        pcall(function()
            if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then d.Transparency = t
            elseif d:IsA("LayerCollector") then d.Enabled = t end
            d:SetAttribute(HIDE_ATTR, nil)
        end)
    end
end

local function hideModel(m)
    for _, d in ipairs(m:GetDescendants()) do
        pcall(function()
            if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
                if d:GetAttribute(HIDE_ATTR) == nil then d:SetAttribute(HIDE_ATTR, d.Transparency) end
                d.Transparency = 1
                if d:IsA("BasePart") then d.CanCollide = false end
            elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
                if d:GetAttribute(HIDE_ATTR) == nil then d:SetAttribute(HIDE_ATTR, d.Enabled) end
                d.Enabled = false
            end
        end)
    end
end

local function showModel(m)
    for _, d in ipairs(m:GetDescendants()) do
        local t = d:GetAttribute(HIDE_ATTR)
        if t ~= nil then
            pcall(function()
                if d:IsA("LayerCollector") then d.Enabled = t else d.Transparency = t end
                d:SetAttribute(HIDE_ATTR, nil)
            end)
        end
    end
end

local function cloneVisual(src)
    local ok, c = pcall(function() return src:Clone() end)
    if not ok or not c then return end
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.Anchored = true; d.CanTouch = false; d.CanQuery = false
        end
    end
    -- Tool solta no workspace pode ser "pega" ao encostar: embrulha num Model
    if c:IsA("Tool") then
        local w = Instance.new("Model")
        for _, ch in ipairs(c:GetChildren()) do ch.Parent = w end
        c:Destroy(); c = w
    end
    return c
end

local visualBase, visualTread
local baseSrcPlot, treadSrcIdx = nil, 0

local function relMove(clone, srcModel, fromPlot, toPlot)
    local fa, fb = plotFrame(fromPlot), plotFrame(toPlot)
    if not fa or not fb then return false end
    clone:PivotTo(fb * fa:Inverse() * srcModel:GetPivot())
    return true
end

local function applyMaxBase()
    local my = myPlot(); if not my then setStatus("Clique 'Minha base e aqui' primeiro") return end
    local plots = workspace:FindFirstChild("Plots")
    local best, bestLv
    for _, p in ipairs(plots:GetChildren()) do
        local lv = tonumber(p:GetAttribute("BaseUpgradeLevel")) or 0
        if p ~= my and p:FindFirstChild("ToUpdate") and (not bestLv or lv > bestLv) then best, bestLv = p, lv end
    end
    local myLv = tonumber(my:GetAttribute("BaseUpgradeLevel")) or 0
    if not best then setStatus("Nenhuma outra base no servidor") return end
    if bestLv <= myLv then setStatus("Sua base ja e a maior do servidor (nv " .. myLv .. ")") return end
    if visualBase then visualBase:Destroy() end
    local c = cloneVisual(best.ToUpdate); if not c then return end
    c.Name = "VisualBase"; c.Parent = folder
    relMove(c, best.ToUpdate, best, my)
    hideModel(my.ToUpdate)
    for _, extra in ipairs({"PlotUpgrade"}) do
        if my:FindFirstChild(extra) then hideModel(my[extra]) end
    end
    visualBase, baseSrcPlot = c, best
    setStatus(("Base nivel %d (copiada do plot %s)"):format(bestLv, best.Name))
end

local function removeMaxBase()
    if visualBase then visualBase:Destroy(); visualBase = nil end
    local my = myPlot()
    if my then
        if my:FindFirstChild("ToUpdate") then showModel(my.ToUpdate) end
        if my:FindFirstChild("PlotUpgrade") then showModel(my.PlotUpgrade) end
    end
    baseSrcPlot = nil
    setStatus("Base original de volta")
end

-- esteiras: workspace.__ClientTreadmillRenders.TreadmillRender_<slot>
local function treadRenders()
    local f = workspace:FindFirstChild("__ClientTreadmillRenders")
    local list = {}
    if not f then return list end
    local plots = workspace:FindFirstChild("Plots")
    local my = myPlot()
    for _, r in ipairs(f:GetChildren()) do
        local slot = r.Name:match("TreadmillRender_(%w+)")
        local p = slot and plots and plots:FindFirstChild(slot)
        if p and p ~= my then table.insert(list, {render = r, plot = p}) end
    end
    return list
end

-- 12 esteiras do jogo (ReplicatedStorage.Assets.Models.Treadmills), da MAXIMA pra basica
local TREAD_ORDER = {"GuardianTreadmill", "AstralTreadmill", "AngelicTreadmill", "CelebrityTreadmill",
    "DemonicTreadmill", "FlameTreadmill", "GoldenTreadmill", "HackerTreadmill", "Lucky BlockTreadmill",
    "Sci-FiTreadmill", "The FreezeTreadmill", "Treadmill"}

local function treadSources()
    local list = {}
    local f
    pcall(function() f = RS.Assets.Models.Treadmills end)
    if f then
        for _, n in ipairs(TREAD_ORDER) do
            local t = f:FindFirstChild(n)
            if t then table.insert(list, t) end
        end
        for _, t in ipairs(f:GetChildren()) do
            if not table.find(TREAD_ORDER, t.Name) then table.insert(list, t) end
        end
    end
    if #list == 0 then   -- plano B: esteiras dos outros jogadores
        for _, e in ipairs(treadRenders()) do table.insert(list, e.render) end
    end
    return list
end

local function boxOf(m)
    local mn, mx
    for _, p in ipairs(m:GetDescendants()) do
        if p:IsA("BasePart") and p.Size.Magnitude < 300 then
            local hs = p.Size / 2
            local a, b = p.Position - hs, p.Position + hs
            mn = mn and Vector3.new(math.min(mn.X, a.X), math.min(mn.Y, a.Y), math.min(mn.Z, a.Z)) or a
            mx = mx and Vector3.new(math.max(mx.X, b.X), math.max(mx.Y, b.Y), math.max(mx.Z, b.Z)) or b
        end
    end
    return mn, mx
end

-- posicao/rotacao da SUA esteira real: medida UMA vez (antes de esconder) e reaproveitada
local treadTarget
local function getTreadTarget(my)
    if treadTarget and treadTarget.slot == my.Name then return treadTarget end
    local f = workspace:FindFirstChild("__ClientTreadmillRenders")
    local mine = f and f:FindFirstChild("TreadmillRender_" .. my.Name)
    local t = {slot = my.Name}
    if mine then
        local mn, mx = boxOf(mine)
        if mn then t.center, t.bottom = (mn + mx) / 2, mn.Y end
        local h = mine:FindFirstChild("Handle")
        if h then t.rot = h.CFrame - h.CFrame.Position end
    end
    if not t.center then
        local tb = my:FindFirstChild("TreadmillBottom")
        if tb then t.center, t.bottom = tb.Position, tb.Position.Y + tb.Size.Y / 2 end
    end
    if not t.rot then
        local fr = plotFrame(my)
        t.rot = fr and (fr - fr.Position) or CFrame.new()
    end
    if t.center then treadTarget = t end
    return t
end

-- velocidade por "raio" de acordo com a esteira (config do jogo; se nao der, tabela por nivel)
local TREAD_GAIN_FALLBACK = {
    ["Treadmill"] = 1, ["The FreezeTreadmill"] = 2, ["Sci-FiTreadmill"] = 3, ["Lucky BlockTreadmill"] = 5,
    ["HackerTreadmill"] = 8, ["GoldenTreadmill"] = 12, ["FlameTreadmill"] = 20, ["DemonicTreadmill"] = 35,
    ["CelebrityTreadmill"] = 50, ["AngelicTreadmill"] = 80, ["AstralTreadmill"] = 150, ["GuardianTreadmill"] = 300,
}
local visualTreadName, visualTreadRate
local function parseRate(txt)
    txt = tostring(txt or ""):gsub("<[^>]->", "")
    local n, suf = txt:match("%+%s*([%d%.,]+)%s*([KkMmBbTt]?)%s*/%s*s")
    if not n then return end
    n = tonumber((n:gsub(",", ".")))
    if not n then return end
    local mult = ({k = 1e3, m = 1e6, b = 1e9, t = 1e12})[suf:lower()] or 1
    return n * mult
end
local function rateFromSign(m)
    for _, t in ipairs(m:GetDescendants()) do
        if t:IsA("TextLabel") or t:IsA("TextButton") then
            local r = parseRate(t.Text)
            if r then return r end
        end
    end
end
local gainCache = {}
local function treadGain(name)
    if not name then return 1 end
    if gainCache[name] then return gainCache[name] end
    local g
    pcall(function()
        local cfg = require(RS.Data.Treadmills.Configs[name])
        if type(cfg) ~= "table" then return end
        local function scan(t, depth)
            if type(t) ~= "table" or depth > 3 or g then return end
            for k, v in pairs(t) do
                local lk = tostring(k):lower()
                if type(v) == "number" and v > 0 and (lk:find("speed") or lk:find("mult") or lk:find("gain") or lk:find("boost")) then
                    g = v; return
                elseif type(v) == "table" then scan(v, depth + 1) end
            end
        end
        scan(cfg, 0)
    end)
    g = g or TREAD_GAIN_FALLBACK[name] or 1
    gainCache[name] = g
    return g
end

local function nextTreadmill()
    local my = myPlot(); if not my then setStatus("Clique 'Minha base e aqui' primeiro") return end
    local list = treadSources()
    if #list == 0 then setStatus("Nenhum modelo de esteira encontrado") return end
    local target = getTreadTarget(my)   -- mede ANTES de esconder a sua
    if not target.center then setStatus("Nao achei sua esteira") return end
    treadSrcIdx = treadSrcIdx % #list + 1
    local src = list[treadSrcIdx]
    if visualTread then visualTread:Destroy() end
    local c = cloneVisual(src); if not c then return end
    c.Name = "VisualTreadmill"; c.Parent = folder
    local h = c:FindFirstChild("Handle") or c:FindFirstChildWhichIsA("BasePart", true)
    if h then c.PrimaryPart = h end
    -- 1) mesma rotacao do Handle da sua esteira real
    local piv = c:GetPivot()
    c:PivotTo(CFrame.new(piv.Position) * target.rot)
    -- 2) centro e chao iguais aos da sua esteira real
    local cmn, cmx = boxOf(c)
    if cmn then
        local cc = (cmn + cmx) / 2
        c:PivotTo(c:GetPivot() + Vector3.new(target.center.X - cc.X, target.bottom - cmn.Y, target.center.Z - cc.Z))
    end
    local f = workspace:FindFirstChild("__ClientTreadmillRenders")
    local mine = f and f:FindFirstChild("TreadmillRender_" .. my.Name)
    if mine then hideModel(mine) end
    if my:FindFirstChild("TreadmillUpgrade") then hideModel(my.TreadmillUpgrade) end
    visualTread = c
    visualTreadName = src.Name
    visualTreadRate = rateFromSign(c) or rateFromSign(src)
    local nome = src.Name:gsub("Treadmill$", "")
    if nome == "" then nome = "Basica" end
    local rate = visualTreadRate or treadGain(src.Name)
    setStatus(("Esteira: %s +%s/s (%d/%d)%s"):format(nome, tostring(rate), treadSrcIdx, #list, treadSrcIdx == 1 and " - MAXIMA" or ""))
end

local function removeTreadmill()
    if visualTread then visualTread:Destroy(); visualTread = nil end
    visualTreadName = nil
    visualTreadRate = nil
    local my = myPlot()
    if my then
        local mine = workspace:FindFirstChild("__ClientTreadmillRenders")
        mine = mine and mine:FindFirstChild("TreadmillRender_" .. my.Name)
        if mine then showModel(mine) end
        if my:FindFirstChild("TreadmillUpgrade") then showModel(my.TreadmillUpgrade) end
    end
    setStatus("Esteira original de volta")
end

-- o jogo pode re-renderizar a sua base/esteira: esconde de novo a cada 3s
task.spawn(function()
    while task.wait(3) do
        if not alive() then break end
        local my = myPlot()
        if my then
            if visualBase and my:FindFirstChild("ToUpdate") then hideModel(my.ToUpdate) end
            if visualTread then
                local f = workspace:FindFirstChild("__ClientTreadmillRenders")
                local mine = f and f:FindFirstChild("TreadmillRender_" .. my.Name)
                if mine then hideModel(mine) end
            end
        end
    end
end)

-- ================= SIMULADOR VISUAL (tudo so na sua tela) =================
-- Auto roubar: ovo do mapa voa ate sua base, choca e vira o pet daquele ovo.
-- Pets geram dinheiro visual. Esteira da velocidade visual. Salva entre sessoes.
local HttpService  = game:GetService("HttpService")
local SIM_FILE = "modvip_sim_save.json"
local sim = {money = 0, speed = 16, stolen = 0, hatched = 0, uiMul = 0}
pcall(function()
    if isfile and isfile(SIM_FILE) then
        local d = HttpService:JSONDecode(readfile(SIM_FILE))
        for k, v in pairs(d) do if sim[k] ~= nil and type(v) == "number" then sim[k] = v end end
    end
end)
local function simSave()
    pcall(function() if writefile then writefile(SIM_FILE, HttpService:JSONEncode(sim)) end end)
end
task.spawn(function() while task.wait(10) do if not alive() then break end simSave() end end)

local function fmtMoney(n)
    local suf = {"", "K", "M", "B", "T", "Qa", "Qi"}
    local i = 1
    while n >= 1000 and i < #suf do n = n / 1000; i = i + 1 end
    return (i == 1 and tostring(math.floor(n)) or (string.format("%.1f", n):gsub("%.0$", ""))) .. suf[i]
end

-- dados dos ovos do mapa: AssetCategory = pet que nasce
local eggCat = {}
local function onEggData(d)
    if type(d) == "table" and d.Uid then
        eggCat[d.Uid] = {cat = d.AssetCategory, area = d.AreaId, pos = d.BottomCFrame and d.BottomCFrame.Position}
    end
end
pcall(function()
    local N = RS.Packages.Networking
    N["RE/EggWorld/FieldEggShifted"].OnClientEvent:Connect(onEggData)
    N["RE/EggWorld/FieldEggBatchShifted"].OnClientEvent:Connect(function(l)
        if type(l) == "table" then for _, d in pairs(l) do onEggData(d) end end
    end)
end)
task.spawn(function()
    pcall(function()
        local snap = RS.Packages.Networking["RF/EggWorld/AskFieldEggSnapshot"]:InvokeServer()
        if type(snap) == "table" then
            for k, d in pairs(snap) do
                if type(d) == "table" then d.Uid = d.Uid or k; onEggData(d) end
            end
        end
    end)
end)

-- ===== o que o JOGO mostra nos pets reais (aprendido olhando as bases dos outros jogadores) =====
-- Gravacao do jogo: cada pet real tem a placa "Data" (DisplayName, PerSecond "$4.6B/s", Odds = raridade).
-- Copiamos essa placa (mesmo visual) e aprendemos renda/raridade de cada pet. Fica salvo em arquivo.
GK = {info = {}, grad = {}, file = "modvip_pet_learn.json", hatchMode = "Rápido", gameFx = true, speedMode = "Flash", treadBonus = 300000, flashChar = true, runSpeed = 300, renderCache = {}, renderPure = {}}
-- "assinatura" do esqueleto: se o modelo nao tem os mesmos ossos/juntas, a animacao do jogo fica toda errada nele
function GK.petSource(name)
    if GK.renderCache[name] then return GK.renderCache[name] end
    local am = RS:FindFirstChild("AssetModels")
    if not am then return end
    local sw = am:FindFirstChild("ToSwap")
    return (sw and sw:FindFirstChild(name)) or am:FindFirstChild(name)
end
function GK.rigSig(m)
    local names = {}
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("Bone") or d:IsA("Motor6D") then table.insert(names, d.Name) end
    end
    table.sort(names)
    local str = table.concat(names, ",")
    local h = 0
    for i = 1, #str do h = (h * 31 + str:byte(i)) % 2147483647 end
    return #names .. ":" .. h
end
-- troca o modelo de um pet ja na base pelo modelo que o jogo usa de verdade
function GK.swapModel(sp, src)
    local ok, m = pcall(function() return src:Clone() end)
    if not ok or not m then return false end
    prep(m)
    m.Name = sp.model.Name
    local center = sp.model:GetPivot() * sp.centerToPivot:Inverse()
    sp.model:Destroy()
    m.Parent = folder
    sp.model, sp.tagLabel, sp.tagIsData, sp.trIdle, sp.trWalk = m, nil, nil, nil, nil
    pcall(function() sp.k = m:GetScale() end)
    sp.k = sp.k or 1
    measure(sp)
    sp.origFoot = math.max(0.5, sp.size.X / sp.k)
    rescale(sp, scale)
    m:PivotTo(center * sp.centerToPivot)
    sp.fromRender = true
    return true
end
-- o servidor avisa quando VOCE sobe/desce da esteira
pcall(function()
    RS.Packages.Networking["RE/Treadmill/RenderStateShifted"].OnClientEvent:Connect(function(plr, on)
        if plr == LP then GK.onTread = on == true end
    end)
end)
pcall(function()
    if isfile and isfile(GK.file) then
        local d = HttpService:JSONDecode(readfile(GK.file))
        if type(d) == "table" then GK.info = d end
    end
end)
GK.MULT = {K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18, Sx = 1e21}
GK.COLORS = {
    Common = Color3.fromRGB(190, 190, 190), Uncommon = Color3.fromRGB(90, 220, 90), Rare = Color3.fromRGB(70, 150, 255),
    Epic = Color3.fromRGB(180, 80, 255), Legendary = Color3.fromRGB(255, 170, 30), Mythic = Color3.fromRGB(255, 60, 90),
    Secret = Color3.fromRGB(60, 60, 60), Cosmic = Color3.fromRGB(120, 90, 255), Eternal = Color3.fromRGB(255, 240, 200),
    Divine = Color3.fromRGB(255, 220, 90),
}
function GK.parseMoney(t)
    t = tostring(t or ""):gsub("<[^>]->", ""):gsub(",", "")
    local n, suf = t:match("([%d%.]+)%s*(%a*)")
    n = tonumber(n)
    if not n then return end
    return n * (GK.MULT[suf] or 1)
end
-- "Pure Jellyfish" -> "Jellyfish" (tira a mutacao da frente)
function GK.baseName(m, display)
    local am = RS:FindFirstChild("AssetModels")
    if not am then return end
    local p = m:GetAttribute("PreparedSourceName")
    if type(p) == "string" and am:FindFirstChild(p) then return p end
    if not display or display == "" then return end
    if am:FindFirstChild(display) then return display end
    local rest = display
    while true do
        local nxt = rest:match("^%S+%s+(.+)$")
        if not nxt then return end
        rest = nxt
        if am:FindFirstChild(rest) then return rest end
    end
end
function GK.scan()
    local f = workspace:FindFirstChild("ClientRenderedAssets")
    if not f then return end
    local changed, gotTemplate = false, false
    local learned = {}
    local pos0 = {}
    for _, m in ipairs(f:GetChildren()) do
        local h = m:FindFirstChild("HumanoidRootPart")
        if h then pos0[m] = h.Position end
    end
    task.wait(0.25)
    for _, m in ipairs(f:GetChildren()) do
        local data = m:FindFirstChild("Data")
        if data and data:IsA("BillboardGui") then
            if not GK.template then
                local c = data:Clone()
                if c then GK.template = c; gotTemplate = true end
            end
            local dn, ps, od = data:FindFirstChild("DisplayName"), data:FindFirstChild("PerSecond"), data:FindFirstChild("Odds")
            local display = dn and (dn.Text:gsub("<[^>]->", "")) or ""
            local name = GK.baseName(m, display)
            if name then
                local e = GK.info[name] or {}
                local inc = ps and GK.parseMoney(ps.Text)
                local pure = display == name
                if inc and inc > 0 then
                    if pure and (not e.pure or inc < e.income) then e.income, e.pure = inc, true; changed = true
                    elseif not e.pure and (not e.income or inc < e.income) then e.income = inc; changed = true end
                end
                local rar = od and (od.Text:gsub("<[^>]->", "")) or ""
                if rar ~= "" then
                    if e.rarity ~= rar then e.rarity = rar; changed = true end
                    local g = od:FindFirstChildOfClass("UIGradient")
                    if g and not GK.grad[rar] then GK.grad[rar] = g:Clone() end
                end
                local ids = {}
                for _, an in ipairs(m:GetDescendants()) do
                    if an:IsA("Animator") then
                        for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
                            if tr.Animation and tr.Animation.AnimationId ~= "" then table.insert(ids, tr.Animation.AnimationId) end
                        end
                    end
                end
                local inner = m:FindFirstChild("Model")
                if inner and inner:IsA("Model") then
                    local sig = GK.rigSig(inner)
                    if e.rig ~= sig then e.rig = sig; changed = true end
                    if not GK.renderCache[name] or (pure and not GK.renderPure[name]) then
                        local old = inner.Archivable
                        inner.Archivable = true
                        local okc, c = pcall(function() return inner:Clone() end)
                        inner.Archivable = old
                        if okc and c then
                            pcall(function() c:ScaleTo(1) end)
                            GK.renderCache[name], GK.renderPure[name] = c, pure
                            local swapped = false
                            for _, sp in ipairs(spawned) do
                                if sp.petName == name and not sp.isEgg and not sp.fromRender and sp.model.Parent then
                                    if GK.swapModel(sp, c) then swapped = true end
                                end
                            end
                            if swapped then learned[name] = true; pcall(layout) end
                        end
                    end
                end
                if ids[1] then
                    local h = m:FindFirstChild("HumanoidRootPart")
                    local moving = h and pos0[m] and (h.Position - pos0[m]).Magnitude > 0.2
                    e.anims = e.anims or {}
                    local slot = moving and "walk" or "idle"
                    if e.anims[slot] ~= ids[1] then e.anims[slot] = ids[1]; changed = true; learned[name] = true end
                end
                GK.info[name] = e
            end
        end
    end
    -- seus pets que estavam sem animacao (ou com a errada) ganham a real assim que ela aparece
    for _, sp in ipairs(spawned) do
        if not sp.isEgg and sp.petName and learned[sp.petName] and sp.model.Parent then
            sp.animated = playAnim(sp.model, sp.petName, sp)
        end
    end
    if changed then pcall(function() if writefile then writefile(GK.file, HttpService:JSONEncode(GK.info)) end end) end
    if gotTemplate then
        -- pets que estavam com a plaquinha simples ganham a placa do jogo
        for _, s in ipairs(spawned) do
            if not s.isEgg and s.tagLabel and not s.tagIsData then
                local a = s.model:FindFirstChild("SimTagAnchor")
                if a then a:Destroy() end
                s.tagLabel = nil
            end
        end
    end
end
function GK.count()
    local n = 0
    for _ in pairs(GK.info) do n = n + 1 end
    return n
end
-- placa igual a dos pets reais: nome, $/s e raridade (com o degrade da raridade)
function GK.tag(s)
    local tpl = GK.template
    if not tpl then return end
    local name = s.petName
    local center = s.model:GetPivot() * s.centerToPivot:Inverse()
    local w = math.clamp(math.max(s.size.X, s.size.Y) * 0.55, 6, 34)
    local h = w * 0.47
    local a = Instance.new("Part")
    a.Name = "SimTagAnchor"; a.Size = Vector3.new(0.2, 0.2, 0.2); a.Transparency = 1
    a.Anchored = true; a.CanCollide = false; a.CanTouch = false; a.CanQuery = false
    a.CFrame = center * CFrame.new(0, s.size.Y / 2 + h * 0.35, 0)
    a.Parent = s.model
    local bb = tpl:Clone()
    bb.Size = UDim2.new(w, 0, h, 0)
    bb.StudsOffset = Vector3.zero
    bb.Adornee = a; bb.Enabled = true; bb.Parent = a
    local e = (name and GK.info[name]) or {}
    local function set(n, txt)
        local l = bb:FindFirstChild(n)
        if l and l:IsA("TextLabel") then l.Text = txt; l.Visible = true return l end
    end
    set("DisplayName", name or "Pet")
    set("Rarity", "")
    local ps = set("PerSecond", "$" .. fmtMoney(s.income or 0) .. "/s")
    local od = set("Odds", e.rarity or "")
    if od then
        local g = od:FindFirstChildOfClass("UIGradient")
        if g then g:Destroy() end
        local src = e.rarity and GK.grad[e.rarity]
        if src then src:Clone().Parent = od
        elseif e.rarity then od.TextColor3 = GK.COLORS[e.rarity] or Color3.new(1, 1, 1) end
    end
    if not ps then a:Destroy() return end
    s.tagIsData = true
    return ps
end
-- raridade de verdade: o servidor manda quando um ovo e entregue (FieldEggRedeemVerdict)
pcall(function()
    RS.Packages.Networking["RE/EggWorld/FieldEggRedeemVerdict"].OnClientEvent:Connect(function(d)
        if GK.faking or type(d) ~= "table" or type(d.AssetCategory) ~= "string" or type(d.Rarity) ~= "string" then return end
        local e = GK.info[d.AssetCategory] or {}
        e.rarity = d.Rarity
        if typeof(d.Color) == "Color3" then e.color = {d.Color.R, d.Color.G, d.Color.B} end
        GK.info[d.AssetCategory] = e
    end)
end)
task.spawn(function()
    while alive() do
        pcall(GK.scan)
        task.wait(8)
    end
end)

-- plaquinha em cima do modelo (parte invisivel dentro do modelo, anda junto)
local function addTag(s)
    if not s.isEgg then
        local ok, tl = pcall(GK.tag, s)
        if ok and tl then return tl end
    end
    local center = s.model:GetPivot() * s.centerToPivot:Inverse()
    local a = Instance.new("Part")
    a.Name = "SimTagAnchor"; a.Size = Vector3.new(0.2, 0.2, 0.2); a.Transparency = 1
    a.Anchored = true; a.CanCollide = false; a.CanTouch = false; a.CanQuery = false
    a.CFrame = center * CFrame.new(0, s.size.Y / 2 + 1.5, 0)
    a.Parent = s.model
    local bb = Instance.new("BillboardGui")
    bb.Name = "SimTag"; bb.AlwaysOnTop = true; bb.MaxDistance = 250
    bb.Size = UDim2.new(0, 150, 0, 40); bb.Adornee = a; bb.Parent = a
    local tl = Instance.new("TextLabel", bb)
    tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
    tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.TextStrokeTransparency = 0.2
    tl.TextColor3 = Color3.fromRGB(255, 230, 80)
    s.tagLabel = tl
    return tl
end

-- renda por segundo (estavel por nome de pet)
local function incomeFor(name)
    local e = name and GK.info[name]
    if e and e.income then return e.income end
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) % 100000 end
    return 10 + (h % 90) * (1 + sim.hatched * 0.1)
end

local function voar(s, fromCF)
    s.flying = true
    local t0, dur = tick(), 2.2
    local a = fromCF.Position
    while tick() - t0 < dur do
        if not s.model.Parent or not s.home then break end
        local k = (tick() - t0) / dur
        local p = a:Lerp(s.home.Position, k) + Vector3.new(0, math.sin(k * math.pi) * 25, 0)
        s.model:PivotTo(CFrame.new(p) * (s.home - s.home.Position) * s.centerToPivot)
        task.wait()
    end
    s.pos = s.home
    s.flying = false
end

local SIM_AREAS = {"Todas", "Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric",
    "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest"}
local simArea = "Todas"
local simAuto = false
local chosenPet           -- pet escolhido na grade do spawner (usado no roubo tambem)
local tripSteal            -- definido na secao do personagem
local charMode = true      -- auto roubar usa o personagem
local HATCH_TIME = 10
local MAX_ITEMS = 40

-- ===== area de cada pet + modelo do ovo de cada pet =====
local AREA_POS = {
    Forest = Vector3.new(591.8, 68.1, -325.6), Lake = Vector3.new(738.1, 68.0, -411.1),
    Desert = Vector3.new(946.4, 69.4, -327.3), Jungle = Vector3.new(1194.4, 68.1, -412.1),
    Snow = Vector3.new(1489.0, 69.3, -317.8), Volcano = Vector3.new(1884.5, 69.3, -400.6),
    ["Abyss Ocean"] = Vector3.new(2278.2, 68.7, -330.1), Prehistoric = Vector3.new(2818.9, 68.1, -401.0),
    Cosmic = Vector3.new(3397.5, 69.6, -322.7),
}
local RARITY_AREA = {
    Common = "Forest", Uncommon = "Lake", Rare = "Desert", SuperRare = "Jungle", Epic = "Snow",
    Legendary = "Volcano", Mythic = "Abyss Ocean", Secret = "Prehistoric", Divine = "Cosmic",
    Cosmic = "Cosmic", Eternal = "Cosmic", Transcendent = "Cosmic", Rainbow = "Cosmic",
    Titan = "Titan Temple", LightDark = "Light Dark", BrainrotGod = "Cosmic", Limited = "Cosmic",
}

-- modelo do ovo do pet (ReplicatedStorage.Assets.Models.Eggs[pet])
local function eggModelFor(name)
    if not name then return end
    local f
    pcall(function() f = RS.Assets.Models.Eggs end)
    return f and f:FindFirstChild(name)
end

local petAreaCache   -- pet -> {area = true, ...} segundo as configs das areas
local function buildPetAreas()
    petAreaCache = {}
    pcall(function()
        local names = {}
        for _, m in ipairs(RS.AssetModels:GetChildren()) do names[m.Name] = true end
        for _, mod in ipairs(RS.Data.Areas.Configs:GetChildren()) do
            local ok, cfg = pcall(require, mod)
            if ok and type(cfg) == "table" then
                local seen = {}
                local function add(n)
                    petAreaCache[n] = petAreaCache[n] or {}
                    petAreaCache[n][mod.Name] = true
                end
                local function scan(t, depth)
                    if type(t) ~= "table" or depth > 6 or seen[t] then return end
                    seen[t] = true
                    for k, v in pairs(t) do
                        if type(v) == "string" and names[v] then add(v) end
                        if type(k) == "string" and names[k] then add(k) end
                        if type(v) == "table" then scan(v, depth + 1) end
                    end
                end
                scan(cfg, 0)
            end
        end
    end)
end

local function petConfig(name)
    local ok, cfg = pcall(function() return require(RS.Data.Assets.Configs[name]) end)
    return ok and type(cfg) == "table" and cfg or nil
end

local KNOWN_AREAS = {}
for _, a in ipairs({"Forest", "Lake", "Desert", "Jungle", "Snow", "Volcano", "Abyss Ocean", "Prehistoric",
    "Cosmic", "Cherry Blossom", "Titan Temple", "Light Dark", "Enchanted Forest"}) do KNOWN_AREAS[a] = true end

-- procura na config do pet um texto que seja nome de area (ex: Area = "Cosmic")
local function areaFromPetConfig(cfg)
    local found
    local seen = {}
    local function scan(t, depth)
        if found or type(t) ~= "table" or depth > 3 or seen[t] then return end
        seen[t] = true
        for k, v in pairs(t) do
            local lk = tostring(k):lower()
            if type(v) == "string" and KNOWN_AREAS[v] and (lk:find("area") or lk:find("biome") or lk:find("zone") or lk:find("world")) then
                found = v return
            end
        end
        for k, v in pairs(t) do
            if type(v) == "string" and KNOWN_AREAS[v] then found = v return end
            if type(v) == "table" then scan(v, depth + 1) end
        end
    end
    scan(cfg, 0)
    return found
end

-- ===== area pela GALERIA de ovos (Assets.Models.Eggs fica organizada por area no eixo Z) =====
-- faixas medidas no scan real do jogo (sem precisar de require, que nao funciona no Xeno)
local Z_BANDS = {
    {-650, -760, "Forest"}, {-760, -870, "Lake"}, {-870, -965, "Desert"}, {-965, -1040, "Jungle"},
    {-1040, -1140, "Snow"}, {-1140, -1257, "Volcano"}, {-1257, -1355, "Abyss Ocean"},
    {-1355, -1450, "Prehistoric"}, {-1450, -1620, "Cosmic"},
}
local function galleryPos(name)
    local m = eggModelFor(name); if not m then return end
    local ok, pos = pcall(function()
        if m:IsA("Model") then return m:GetPivot().Position end
        if m:IsA("BasePart") then return m.Position end
        local p = m:FindFirstChildWhichIsA("BasePart", true)
        return p and p.Position
    end)
    return ok and pos or nil
end
local function areaFromGallery(name)
    local pos = galleryPos(name); if not pos then return end
    if math.abs(pos.X + 740) > 150 then return end          -- fora da galeria (ovos especiais)
    for _, b in ipairs(Z_BANDS) do
        if pos.Z <= b[1] and pos.Z > b[2] then return b[3] end
    end
end

-- memoria: pet -> area aprendido dos ovos que nascem no mapa (salvo em arquivo)
local AREA_MEM_FILE = "modvip_pet_areas.json"
local areaMem = {}
pcall(function()
    if isfile and isfile(AREA_MEM_FILE) then
        local d = game:GetService("HttpService"):JSONDecode(readfile(AREA_MEM_FILE))
        if type(d) == "table" then areaMem = d end
    end
end)
task.spawn(function()
    local last = ""
    while task.wait(15) do
        if not alive() then break end
        local changed = false
        for _, d in pairs(eggCat) do
            if d.cat and d.area and areaMem[d.cat] ~= d.area then areaMem[d.cat] = d.area; changed = true end
        end
        if changed then
            pcall(function()
                if writefile then writefile(AREA_MEM_FILE, game:GetService("HttpService"):JSONEncode(areaMem)) end
            end)
        end
    end
end)

-- area pelos VIZINHOS na galeria: pets de area conhecida (memoria) com ovo perto do ovo deste pet
local gposCache = {}
local function gpos(name)
    if gposCache[name] == nil then gposCache[name] = galleryPos(name) or false end
    return gposCache[name] or nil
end
local function areaFromNeighbors(name)
    local pos = gpos(name); if not pos then return end
    local known = {}
    for pet, ar in pairs(areaMem) do known[pet] = ar end
    for _, d in pairs(eggCat) do if d.cat and d.area then known[d.cat] = d.area end end
    local list = {}
    for pet, ar in pairs(known) do
        if pet ~= name then
            local gp = gpos(pet)
            if gp then
                local dist = (Vector3.new(gp.X, 0, gp.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
                table.insert(list, {ar = ar, d = dist, pet = pet})
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    if #list == 0 or list[1].d > 120 then return nil, list[1] end
    -- voto dos 3 vizinhos mais perto (peso pela distancia)
    local votes = {}
    for i = 1, math.min(3, #list) do
        local e = list[i]
        votes[e.ar] = (votes[e.ar] or 0) + 1 / math.max(e.d, 1)
    end
    local best, bv
    for ar, v in pairs(votes) do if not bv or v > bv then best, bv = ar, v end end
    return best, list[1]
end

-- area do pet: ovos vistos no mapa > memoria > galeria de ovos > config do pet > config de UMA area > raridade
local function petArea(name)
    if not name then return end
    for _, d in pairs(eggCat) do
        if d.cat == name and d.area then return d.area, "ovo no mapa" end
    end
    if areaMem[name] then return areaMem[name], "memoria" end
    local nb, near = areaFromNeighbors(name)
    if nb then return nb, "vizinho na galeria: " .. near.pet end
    local g = areaFromGallery(name)
    if g then return g, "galeria de ovos" end
    local cfg = petConfig(name)
    local a = cfg and areaFromPetConfig(cfg)
    if a then return a, "config do pet" end
    for _, d in pairs(eggCat) do
        if d.cat == name and d.area then return d.area, "ovo no mapa" end
    end
    if not petAreaCache then buildPetAreas() end
    local set = petAreaCache[name]
    if set then
        local list = {}
        for ar in pairs(set) do table.insert(list, ar) end
        if #list == 1 then return list[1], "config da area" end
    end
    local r = cfg and (cfg.Rarity or cfg.rarity)
    if r and RARITY_AREA[r] then return RARITY_AREA[r], "raridade " .. tostring(r) end
    if set then
        local list = {}
        for ar in pairs(set) do table.insert(list, ar) end
        table.sort(list)
        return list[1], "varias areas: " .. table.concat(list, ",")
    end
end

-- texto com tudo que o jogo diz sobre o pet (pra diagnostico)
local function petInfoText(name)
    local o = {"pet: " .. tostring(name)}
    local a, src = petArea(name)
    table.insert(o, "area escolhida: " .. tostring(a) .. " (" .. tostring(src) .. ")")
    if not petAreaCache then buildPetAreas() end
    local set = petAreaCache[name] or {}
    local l = {}
    for ar in pairs(set) do table.insert(l, ar) end
    table.insert(o, "aparece nas configs das areas: " .. table.concat(l, ", "))
    local seenMap = {}
    for _, d in pairs(eggCat) do if d.cat == name then seenMap[d.area or "?"] = true end end
    l = {}
    for ar in pairs(seenMap) do table.insert(l, ar) end
    table.insert(o, "ovos dele vistos no mapa em: " .. table.concat(l, ", "))
    table.insert(o, "modelo de ovo: " .. tostring(eggModelFor and eggModelFor(name) ~= nil))
    local gp = galleryPos(name)
    table.insert(o, "posicao na galeria: " .. (gp and string.format("x=%.0f z=%.0f", gp.X, gp.Z) or "nil") .. " -> " .. tostring(areaFromGallery(name)))
    table.insert(o, "memoria: " .. tostring(areaMem[name]))
    local nb, near = areaFromNeighbors(name)
    table.insert(o, "vizinho: " .. tostring(nb) .. " | mais perto: " .. (near and (near.pet .. " (" .. near.ar .. ") a " .. math.floor(near.d)) or "nenhum"))
    local cfg = petConfig(name)
    if cfg then
        local function dump(t, pre, depth)
            if depth > 2 then return end
            for k, v in pairs(t) do
                if type(v) == "table" then
                    table.insert(o, pre .. tostring(k) .. " = {")
                    dump(v, pre .. "  ", depth + 1)
                    table.insert(o, pre .. "}")
                else
                    table.insert(o, pre .. tostring(k) .. " = " .. tostring(v):sub(1, 60))
                end
                if #o > 120 then return end
            end
        end
        dump(cfg, "  ", 0)
    else
        table.insert(o, "config do pet: require falhou")
    end
    return table.concat(o, "\n")
end

-- centro da area: media dos ovos vistos la; senao coordenada conhecida
local function areaPos(area)
    local sum, n = Vector3.zero, 0
    for _, d in pairs(eggCat) do
        if d.area == area and d.pos then sum = sum + d.pos; n = n + 1 end
    end
    if n > 0 then return sum / n end
    local f = workspace:FindFirstChild("AreaEggSlotsClient")
    if f then
        for _, m in ipairs(f:GetChildren()) do
            local info = eggCat[m.Name]
            local a = (info and info.area) or m.Name:match("_([%a ]+):Slot_")
            if a == area and m:IsA("Model") then return m:GetPivot().Position end
        end
    end
    return AREA_POS[area]
end

-- um ovo do mapa que esteja nessa area (o mais perto do centro)
local function eggInArea(area)
    local f = workspace:FindFirstChild("AreaEggSlotsClient"); if not f then return end
    local center = areaPos(area)
    local best, bd
    for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") then
            local info = eggCat[m.Name]
            local a = (info and info.area) or m.Name:match("_([%a ]+):Slot_")
            if a == area then
                local d = center and (m:GetPivot().Position - center).Magnitude or 0
                if not bd or d < bd then best, bd = m, d end
            end
        end
    end
    return best
end


local function eggOfPet(name)
    local f = workspace:FindFirstChild("AreaEggSlotsClient"); if not f or not name then return end
    for _, m in ipairs(f:GetChildren()) do
        local info = eggCat[m.Name]
        if m:IsA("Model") and info and info.cat == name then return m end
    end
end

local function pickEgg()
    local f = workspace:FindFirstChild("AreaEggSlotsClient"); if not f then return end
    local list = {}
    for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") then
            local info = eggCat[m.Name]
            local area = (info and info.area) or m.Name:match("_([%a ]+):Slot_")
            if simArea == "Todas" or area == simArea then table.insert(list, {m = m, info = info}) end
        end
    end
    if #list == 0 then return end
    return list[math.random(#list)]
end

-- ===== efeitos copiados da gravacao do jogo (ids reais de som/animacao) =====
GK.SND_PLACE = "rbxassetid://74146265484496"     -- ovo plantado
GK.SND_DETECT = "rbxassetid://96595477884583"    -- guardiao acordou
GK.SND_SLEEP = "rbxassetid://129416806869914"    -- guardiao dormiu
GK.ANIM_CARRY = "rbxassetid://102039335618606"   -- personagem carregando ovo
GK.ANIM_CHASE = "rbxassetid://136832792656489"   -- guardiao correndo
GK.ANIM_RETURN = "rbxassetid://113947385873952"  -- guardiao voltando pra casa
GK.ANIM_SLEEP = "rbxassetid://119006758941979"   -- guardiao dormindo
-- tempo pra chocar por raridade (Real = tempos do jogo; Rapido = pra ver logo)
GK.HATCH = {
    ["Rápido"] = {Common = 10, Uncommon = 12, Rare = 15, Epic = 20, Legendary = 25, Mythic = 30, Cosmic = 35, Secret = 40, Eternal = 45, Divine = 50},
    Real = {Common = 20, Uncommon = 25, Rare = 40, Epic = 75, Legendary = 120, Mythic = 240, Cosmic = 480, Secret = 5400, Eternal = 14400, Divine = 43200},
}
function GK.hatchTime(cat)
    local e = cat and GK.info[cat]
    local t = GK.HATCH[GK.hatchMode] or GK.HATCH["Rápido"]
    return (e and e.rarity and t[e.rarity]) or (GK.hatchMode == "Real" and 60 or HATCH_TIME)
end
function GK.fmtTime(t)
    if t >= 3600 then return string.format("%dh %dm", math.floor(t / 3600), math.floor(t % 3600 / 60)) end
    if t >= 60 then return string.format("%dm %ds", math.floor(t / 60), t % 60) end
    return t .. "s"
end
function GK.sound(id, pos, vol)
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
    p.Transparency = 1; p.Size = Vector3.new(0.2, 0.2, 0.2); p.Position = pos; p.Parent = folder
    local s = Instance.new("Sound")
    s.SoundId = id; s.Volume = vol or 0.8; s.Parent = p
    s:Play()
    game:GetService("Debris"):AddItem(p, 6)
end
function GK.anim(model, id, speed, prio)
    local ac = model:FindFirstChildWhichIsA("Humanoid", true) or model:FindFirstChildWhichIsA("AnimationController", true)
    if not ac then return end
    local an = ac:FindFirstChildOfClass("Animator") or Instance.new("Animator", ac)
    local a = Instance.new("Animation")
    a.AnimationId = id
    local ok, tr = pcall(function() return an:LoadAnimation(a) end)
    if not ok or not tr then return end
    tr.Looped = true
    if prio then pcall(function() tr.Priority = prio end) end
    tr:Play(0.15)
    if speed then tr:AdjustSpeed(speed) end
    return tr
end
function GK.stopAnims(model)
    for _, an in ipairs(model:GetDescendants()) do
        if an:IsA("Animator") then
            for _, t in ipairs(an:GetPlayingAnimationTracks()) do t:Stop(0.2) end
        end
    end
end
-- terra voando + anel no chao (igual quando o jogo planta o ovo)
function GK.plantFx(pos)
    GK.sound(GK.SND_PLACE, pos)
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder; ring.Anchored = true
    ring.CanCollide = false; ring.CanTouch = false; ring.CanQuery = false
    ring.Color = Color3.fromRGB(120, 85, 50); ring.Material = Enum.Material.Ground
    ring.Size = Vector3.new(0.12, 1, 1)
    ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = folder
    local chunks = {}
    for _ = 1, 9 do
        local c = Instance.new("Part")
        c.Anchored = true; c.CanCollide = false; c.CanTouch = false; c.CanQuery = false
        c.Color = Color3.fromRGB(110 + math.random(0, 30), 75, 45); c.Material = Enum.Material.Ground
        c.Size = Vector3.new(0.6, 0.42, 0.6) * (0.8 + math.random() * 0.6)
        c.Parent = folder
        local ang = math.random() * math.pi * 2
        table.insert(chunks, {p = c, d = Vector3.new(math.cos(ang), 0, math.sin(ang)) * (1.5 + math.random() * 2), up = 2 + math.random() * 2})
    end
    task.spawn(function()
        for i = 1, 25 do
            local k = i / 25
            ring.Size = Vector3.new(0.12, 1 + k * 7, 1 + k * 7)
            ring.Transparency = k
            for _, c in ipairs(chunks) do
                c.p.CFrame = CFrame.new(pos + c.d * k + Vector3.new(0, math.sin(k * math.pi) * c.up, 0)) * CFrame.Angles(k * 4, k * 3, 0)
                c.p.Transparency = math.max(0, k * 1.4 - 0.4)
            end
            task.wait(0.03)
        end
        ring:Destroy()
        for _, c in ipairs(chunks) do c.p:Destroy() end
    end)
end
-- ovo pronto: brilho pulsando + botao "Hatch!" (so na sua tela)
function GK.ready(s)
    local done = false
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 245, 170); hl.OutlineColor = Color3.new(1, 1, 1)
    hl.FillTransparency = 1; hl.OutlineTransparency = 0.3; hl.Adornee = s.model; hl.Parent = s.model
    local center = s.model:GetPivot() * s.centerToPivot:Inverse()
    local pp = Instance.new("Part")
    pp.Name = "HatchPrompt"; pp.Size = Vector3.new(1, 1, 1); pp.Transparency = 1
    pp.Anchored = true; pp.CanCollide = false; pp.CanTouch = false; pp.CanQuery = false
    pp.CFrame = center; pp.Parent = s.model
    local pr = Instance.new("ProximityPrompt")
    pr.ActionText = "Hatch!"; pr.ObjectText = "Hatch!"; pr.HoldDuration = 0
    pr.RequiresLineOfSight = false; pr.MaxActivationDistance = math.max(14, s.size.X + 6)
    pr.Parent = pp
    pr.Triggered:Connect(function() done = true end)
    task.spawn(function()
        while not done and hl.Parent do
            for i = 0, 12 do
                if done then break end
                hl.FillTransparency = 1 - math.sin(i / 12 * math.pi) * 0.55
                task.wait(0.05)
            end
            task.wait(1)
        end
    end)
    return {
        wait = function()
            local t0 = tick()
            while not done and s.model.Parent and alive() do
                if simAuto and tick() - t0 > 2 then break end   -- auto: choca sozinho
                if tick() - t0 > 120 then break end
                task.wait(0.2)
            end
        end,
        stop = function()
            done = true
            pcall(function() hl:Destroy() end)
            pcall(function() pp:Destroy() end)
        end,
    }
end
-- ovo treme, brilha e estoura
function GK.hatchFx(s)
    local base = s.model:GetPivot()
    for i = 1, 24 do
        if not s.model.Parent then return end
        local a = math.sin(i * 1.4) * math.rad(3 + i * 0.7)
        s.model:PivotTo(base * CFrame.Angles(a * 0.4, 0, a))
        task.wait(0.05)
    end
    local center = (base * s.centerToPivot:Inverse()).Position
    GK.sound(GK.SND_PLACE, center, 1)
    local ball = Instance.new("Part")
    ball.Shape = Enum.PartType.Ball; ball.Material = Enum.Material.Neon; ball.Color = Color3.fromRGB(255, 250, 210)
    ball.Anchored = true; ball.CanCollide = false; ball.CanTouch = false; ball.CanQuery = false
    ball.Size = Vector3.new(1, 1, 1); ball.Position = center; ball.Parent = folder
    local att = Instance.new("Attachment", ball)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"; pe.LightEmission = 1
    pe.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255))
    pe.Speed = NumberRange.new(10, 22); pe.SpreadAngle = Vector2.new(180, 180)
    pe.Lifetime = NumberRange.new(0.5, 0.9); pe.Rate = 0
    pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0)})
    pe.Parent = att
    pe:Emit(60)
    task.spawn(function()
        local big = math.max(4, s.size.X * 1.6)
        for i = 1, 15 do
            ball.Size = Vector3.new(1, 1, 1) * (1 + (big - 1) * i / 15)
            ball.Transparency = i / 15
            task.wait(0.025)
        end
        task.wait(1)
        ball:Destroy()
    end)
end
-- guardiao da area acorda ("!" + som), corre atras de voce, volta pra casa e dorme (copia; o real some so pra voce)
function GK.guardChase(area, target)
    local real
    pcall(function() real = workspace.World.Areas.GuardAreas[area].Guard end)
    if not real then return end
    local ok, c = pcall(function() return real:Clone() end)
    if not ok or not c then return end
    prep(c)
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("ProximityPrompt") or d:IsA("BillboardGui") or d:IsA("Highlight") then d:Destroy() end
    end
    c.Name = "Visual_Guard"; c.Parent = folder
    local home = real:GetPivot()
    c:PivotTo(home)
    hideModel(real)
    local _, gsize = c:GetBoundingBox()
    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 40, 40); hl.FillTransparency = 0.75
    hl.OutlineColor = Color3.fromRGB(255, 90, 90); hl.Adornee = c; hl.Parent = c
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(60, 60); bb.StudsOffset = Vector3.new(0, gsize.Y / 2 + 2, 0)
    bb.AlwaysOnTop = true; bb.Adornee = c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart", true); bb.Parent = c
    local tl = Instance.new("TextLabel", bb)
    tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1; tl.Text = "!"
    tl.Font = Enum.Font.GothamBlack; tl.TextScaled = true; tl.TextColor3 = Color3.fromRGB(255, 50, 50)
    tl.TextStrokeTransparency = 0
    GK.sound(GK.SND_DETECT, home.Position, 1)
    task.spawn(function()
        pcall(function()
            local cur = home
            local function stepTo(goal, spd, maxT)
                local t0 = tick()
                while c.Parent and alive() and (not maxT or tick() - t0 < maxT) do
                    local dt = RunService.Heartbeat:Wait()
                    local gp = typeof(goal) == "Instance" and goal.Position or goal
                    if typeof(goal) == "Instance" and not goal.Parent then break end
                    local d = Vector3.new(gp.X - cur.X, 0, gp.Z - cur.Z)
                    if d.Magnitude < 1 then break end
                    local np = cur.Position + d.Unit * math.min(d.Magnitude, spd * dt)
                    cur = CFrame.lookAt(np, np + d.Unit)
                    c:PivotTo(cur)
                end
            end
            task.wait(0.6)    -- "Waking"
            GK.anim(c, GK.ANIM_CHASE, 5)
            stepTo(target, 95, 3.5)    -- "Chasing" (~95 studs/s, como na gravacao)
            pcall(function() hl:Destroy(); bb:Destroy() end)
            GK.stopAnims(c)
            GK.anim(c, GK.ANIM_RETURN, 1)
            stepTo(home.Position, 45, 8)   -- "ReturningHome"
            c:PivotTo(home)
            GK.stopAnims(c)
            GK.anim(c, GK.ANIM_SLEEP, 1)   -- "Sleeping"
            GK.sound(GK.SND_SLEEP, home.Position)
            task.wait(1.5)
        end)
        pcall(function() c:Destroy() end)
        showModel(real)
    end)
end
-- chama o efeito do PROPRIO jogo (so na sua tela): ex. o aviso de raridade ao entregar o ovo
function GK.fireGame(evName, ...)
    local ev = RS.Packages.Networking:FindFirstChild(evName)
    if not ev then return false end
    local args = table.pack(...)
    local fired = false
    GK.faking = true
    if getconnections then
        pcall(function()
            for _, cn in ipairs(getconnections(ev.OnClientEvent)) do
                if cn.Function then
                    fired = true
                    task.spawn(pcall, cn.Function, table.unpack(args, 1, args.n))
                end
            end
        end)
    end
    if not fired and firesignal then fired = pcall(firesignal, ev.OnClientEvent, table.unpack(args, 1, args.n)) end
    GK.faking = false
    return fired
end
-- rastro de raio amarelo/laranja (estilo Flash) entre dois pontos
function GK.bolt(a, b)
    local d = (b - a).Magnitude
    if d < 2 then return end
    local n = math.clamp(math.floor(d / 25), 3, 8)
    local segs, prev = {}, a
    for i = 1, n do
        local p = a:Lerp(b, i / n)
        if i < n then p = p + Vector3.new((math.random() - 0.5) * 5, (math.random() - 0.5) * 4, (math.random() - 0.5) * 5) end
        local len = (p - prev).Magnitude
        if len > 0.05 then
            local seg = Instance.new("Part")
            seg.Anchored = true; seg.CanCollide = false; seg.CanTouch = false; seg.CanQuery = false
            seg.Material = Enum.Material.Neon
            seg.Color = math.random() < 0.7 and Color3.fromRGB(255, 220, 40) or Color3.fromRGB(255, 110, 20)
            seg.Size = Vector3.new(0.4, 0.4, len)
            seg.CFrame = CFrame.lookAt((prev + p) / 2, p)
            seg.Parent = folder
            table.insert(segs, seg)
        end
        prev = p
    end
    task.spawn(function()
        for i = 1, 8 do
            for _, g in ipairs(segs) do g.Transparency = i / 8 end
            task.wait(0.04)
        end
        for _, g in ipairs(segs) do g:Destroy() end
    end)
end
-- ovo reserva quando o pet nao tem modelo de ovo proprio (antes dava erro no roubo)
function GK.fallbackEgg(area)
    local f = workspace:FindFirstChild("AreaEggSlotsClient")
    if f then
        for _, m in ipairs(f:GetChildren()) do
            local info = eggCat[m.Name]
            if m:IsA("Model") and m:FindFirstChildWhichIsA("BasePart", true)
                and (not area or (info and info.area == area) or m.Name:find(area, 1, true)) then
                return m
            end
        end
    end
    local ok, list = pcall(function() return RS.Assets.Models.Eggs:GetChildren() end)
    if ok and list and #list > 0 then return list[math.random(#list)] end
    if not GK.eggTpl then
        local m = Instance.new("Model")
        local pt = Instance.new("Part")
        pt.Size = Vector3.new(2, 2, 2); pt.Color = Color3.fromRGB(250, 240, 210); pt.Material = Enum.Material.SmoothPlastic
        local sm = Instance.new("SpecialMesh", pt)
        sm.MeshType = Enum.MeshType.Sphere; sm.Scale = Vector3.new(1, 1.3, 1)
        pt.Parent = m; m.PrimaryPart = pt
        GK.eggTpl = m
    end
    return GK.eggTpl
end
function GK.redeem(cat, pos)
    if not GK.gameFx or not cat or not pos then return end
    local e = GK.info[cat] or {}
    local r = e.rarity or "Common"
    local col = (e.color and Color3.new(e.color[1], e.color[2], e.color[3])) or GK.COLORS[r] or Color3.fromRGB(151, 151, 151)
    GK.fireGame("RE/EggWorld/FieldEggRedeemVerdict", {Rarity = r, Position = pos, Color = col, AssetCategory = cat, DisplayName = cat .. " Egg"})
end

local simPopup  -- definido na GUI do simulador

-- igual o jogo: planta (terra voando) -> contagem -> brilha pronto -> "Hatch!" -> treme e estoura
local function chocar(s, cat)
    pcall(function()
        local c = s.model:GetPivot() * s.centerToPivot:Inverse()
        GK.plantFx(Vector3.new(c.X, c.Y - s.size.Y / 2, c.Z))
    end)
    for t = GK.hatchTime(cat), 1, -1 do
        if not s.model.Parent or not alive() then return end
        if s.tagLabel then s.tagLabel.Text = "🥚 " .. (cat or "Ovo") .. "\n" .. GK.fmtTime(t) end
        task.wait(1)
    end
    if not s.model.Parent or not alive() then return end
    if s.tagLabel then s.tagLabel.Text = "✨ " .. (cat or "Ovo") .. "\nPronto! Hatch!" end
    local rd = GK.ready(s)
    rd.wait()
    rd.stop()
    if not s.model.Parent or not alive() then return end
    if s.tagLabel then s.tagLabel.Text = "🐣 Chocando..." end
    GK.hatchFx(s)
    local idx = table.find(spawned, s)
    if idx then table.remove(spawned, idx) end
    s.model:Destroy()
    local am = RS:FindFirstChild("AssetModels"); if not am then return end
    local src = cat and am:FindFirstChild(cat)
    if not src then local all = am:GetChildren(); src = all[math.random(#all)] end
    local ok, ps = spawnModel(src, src.Name)
    if ok and ps then
        sim.hatched = sim.hatched + 1
        ps.income = incomeFor(src.Name)
        addTag(ps)
        if simPopup then simPopup("🐣 Nasceu: " .. src.Name) end
    end
end

local function simStealOne()
    if not myPlot() then setStatus("Clique 'Minha base e aqui' primeiro") return end
    if #spawned >= MAX_ITEMS then if simPopup then simPopup("Base cheia! (" .. MAX_ITEMS .. ")") end return end
    local e
    local own = chosenPet and eggOfPet(chosenPet)
    if not own and chosenPet then
        local ar = petArea(chosenPet)
        own = ar and eggInArea(ar)
    end
    if own then e = {m = own, info = eggCat[own.Name]} else e = pickEgg() end
    if not e then if simPopup then simPopup("Sem ovos dessa area no mapa") end return end
    local wantCat = chosenPet or (e.info and e.info.cat)
    local c = cloneVisual(eggModelFor(wantCat) or e.m); if not c then return end
    hideModel(e.m)
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and (p.Name == "Hitbox" or p.Name == "CustomBoundingBox") then p.Transparency = 1 end
    end
    c.Name = "Visual_SimEgg"; c.Parent = folder
    local s = {model = c, phase = 0, nextGoal = 0, still = true, animated = true, isEgg = true, k = 1}
    measure(s); s.origFoot = math.max(0.5, s.size.X)
    table.insert(spawned, s)
    layout()
    sim.stolen = sim.stolen + 1
    local cat = chosenPet or (e.info and e.info.cat)
    if simPopup then simPopup("🥚 Roubou: " .. (cat or "Ovo")) end
    voar(s, e.m:GetPivot())
    pcall(GK.redeem, cat, s.home and s.home.Position)
    addTag(s)
    task.spawn(chocar, s, cat)
end

-- dinheiro: soma a renda dos pets a cada segundo e mostra $/s em cima deles
task.spawn(function()
    while task.wait(1) do
        if not alive() then break end
        local total = 0
        for _, s in ipairs(spawned) do
            if not s.isEgg then
                if not s.income then s.income = incomeFor(s.petName or (s.model.Name:gsub("^Visual_", ""))) end
                if not s.tagLabel and s.home and not s.flying then pcall(addTag, s) end
                if s.tagLabel then s.tagLabel.Text = s.tagIsData and ("$" .. fmtMoney(s.income) .. "/s") or ("💰 $" .. fmtMoney(s.income) .. "/s") end
                total = total + s.income
            end
        end
        sim.money = sim.money + total
        sim.income = total
    end
end)

-- auto roubar visual
task.spawn(function()
    while task.wait(4) do
        if not alive() then break end
        if simAuto then
            if charMode and tripSteal then pcall(tripSteal) else pcall(simStealOne) end
        end
    end
end)

-- numeros DO JOGO (+4 com tenis): troca pelo valor da esteira visual, so na sua tela
-- intercepta RE/Treadmill/SpeedGained antes do jogo desenhar (precisa de getconnections)
local G = (getgenv and getgenv()) or {}
local speedHookMsg = "sem getconnections no executor"
pcall(function()
    if G.MV_SpeedHook then speedHookMsg = "ok" return end
    if not getconnections then return end
    local ev = RS.Packages.Networking["RE/Treadmill/SpeedGained"]
    local fns = {}
    for _, c in ipairs(getconnections(ev.OnClientEvent)) do
        local f = c.Function
        if f then
            table.insert(fns, f)
            pcall(function() c:Disable() end)
        end
    end
    if #fns == 0 then speedHookMsg = "nao achei o handler do jogo" return end
    ev.OnClientEvent:Connect(function(amount, ...)
        local r = G.MV_TreadRate
        if r and type(amount) == "number" then amount = r end
        for _, f in ipairs(fns) do task.spawn(f, amount, ...) end
    end)
    G.MV_SpeedHook = true
    speedHookMsg = "ok"
end)

-- troca o TEXTO "+4" que o jogo desenha pelo valor da esteira visual (so na sua tela)
local rewriteCount = 0
local function onTreadmillNow()
    return G.MV_TreadRate ~= nil and G.MV_OnTread == true
end
local function fixLabel(t)
    if not (t:IsA("TextLabel") or t:IsA("TextButton")) then return end
    local function apply()
        if not onTreadmillNow() or t:GetAttribute("MV_Fixed") == t.Text then return end
        local plain = t.Text:gsub("<[^>]->", "")
        local n = plain:match("^%s*%+%s*(%d+)%s*$")
        if not n or plain:find("%$") then return end
        local newTxt = t.Text:gsub("%+%s*" .. n, "+" .. fmtMoney(G.MV_TreadRate), 1)
        t:SetAttribute("MV_Fixed", newTxt)
        t.Text = newTxt
        rewriteCount = rewriteCount + 1
    end
    apply()
    t:GetPropertyChangedSignal("Text"):Connect(apply)
end
local function watch(rootObj)
    rootObj.DescendantAdded:Connect(function(d)
        if alive() and (d:IsA("TextLabel") or d:IsA("TextButton")) then pcall(fixLabel, d) end
    end)
end
pcall(function() watch(LP:WaitForChild("PlayerGui")) end)
pcall(function() watch(workspace) end)

-- esteira: em cima do chao da esteira do SEU plot -> ganha velocidade visual
task.spawn(function()
    while task.wait(1) do
        if not alive() then break end
        G.MV_TreadRate = GK.treadBonus or (visualTread and ((visualTreadRate) or treadGain(visualTreadName))) or nil
        local my, r = myPlot(), root()
        local tb = my and my:FindFirstChild("TreadmillBottom")
        local onIt = GK.onTread == true
        if tb and r and not onIt then
            local l = tb.CFrame:PointToObjectSpace(r.Position)
            onIt = math.abs(l.X) < tb.Size.X / 2 + 2 and math.abs(l.Z) < tb.Size.Z / 2 + 2 and l.Y > -3 and l.Y < 10
        end
        G.MV_OnTread = onIt
        if onIt then
            local gain = G.MV_TreadRate or treadGain(nil)
            sim.speed = sim.speed + gain
            if simPopup and rewriteCount == 0 then simPopup("+" .. fmtMoney(gain) .. " ⚡ Velocidade", true) end
        end
    end
end)

-- ================= ROUBO COM PERSONAGEM (visual) =================
-- Uma COPIA do seu avatar faz a viagem (o real fica parado e invisivel so pra voce).
-- Vai ate o ovo, pega, leva pra base, volta, monta no monstro pai e volta montado.
local Camera = workspace.CurrentCamera
local selectedEgg, selectHL
local selecting = false
local tripBusy = false
local function isTripBusy() return tripBusy end
local tripCancel = false

local ANIM_FALLBACK = {
    run  = "rbxassetid://507767714",
    walk = "rbxassetid://507777826",
    idle = "rbxassetid://507766388",
    sit  = "rbxassetid://2506281703",
}

local function eggModelFrom(part)
    local f = workspace:FindFirstChild("AreaEggSlotsClient")
    if not f then return end
    while part and part.Parent and part.Parent ~= f do part = part.Parent end
    if part and part.Parent == f then return part end
end

local mouse = LP:GetMouse()
mouse.Button1Down:Connect(function()
    if not selecting or not alive() then return end
    local m = eggModelFrom(mouse.Target)
    if not m then return end
    selectedEgg, selecting = m, false
    if selectHL then selectHL:Destroy() end
    selectHL = Instance.new("Highlight")
    selectHL.FillColor = Color3.fromRGB(255, 200, 0); selectHL.OutlineColor = Color3.new(1, 1, 1)
    selectHL.FillTransparency = 0.4; selectHL.Adornee = m; selectHL.Parent = folder
    local info = eggCat[m.Name]
    if simPopup then simPopup("🎯 Selecionado: " .. ((info and info.cat) or "Ovo")) end
end)

local function makeAvatar()
    local ch = (GK.skinModel and GK.skinModel.Parent and GK.skinModel) or LP.Character
    if not ch then return end
    local prevArch = ch.Archivable
    ch.Archivable = true
    local ok, av = pcall(function() return ch:Clone() end)
    ch.Archivable = prevArch
    if not ok or not av then return end
    for _, d in ipairs(av:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Tool") then
            d:Destroy()
        elseif d:IsA("BasePart") then
            d.CanCollide = false; d.CanTouch = false; d.CanQuery = false; d.Massless = true; d.Anchored = false
        end
    end
    local hum = av:FindFirstChildOfClass("Humanoid")
    local hrp = av:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then av:Destroy() return end
    pcall(function() hum.EvaluateStateMachine = true end)
    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    hum.PlatformStand = true
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
    hrp.Anchored = true
    av.Name = "VisualAvatar"; av.Parent = folder
    return av, hum, hrp
end

local function animIdFromAnimate(kind)
    local a = LP.Character and LP.Character:FindFirstChild("Animate")
    local f = a and a:FindFirstChild(kind)
    local an = f and f:FindFirstChildOfClass("Animation")
    return an and an.AnimationId ~= "" and an.AnimationId or nil
end

local function avPlay(hum, kind)
    local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0.15) end
    local id = animIdFromAnimate(kind) or ANIM_FALLBACK[kind]
    if not id then return end
    local an = Instance.new("Animation"); an.AnimationId = id
    local ok, tr = pcall(function() return animator:LoadAnimation(an) end)
    if ok and tr then tr.Looped = true; tr:Play(0.15) end
end

local function setRealHidden(h)
    local ch = LP.Character; if not ch then return end
    for _, p in ipairs(ch:GetDescendants()) do
        if p:IsA("BasePart") or p:IsA("Decal") then p.LocalTransparencyModifier = h and 1 or 0 end
    end
end

-- velocidade da copia usa a velocidade VISUAL ganha na esteira
local function avSpeed()
    local base = math.clamp(1600 + (sim.speed or 0) * 2, 1600, 20000)
    local m = GK.speedMode
    if m == "Flash" then return math.max(15000, base * 5) end
    if m == "Super Flash" then return math.max(60000, base * 15) end
    if m == "Instantâneo" then return 2e6 end
    return base
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- anda/corre em linha reta (altura fixa); onStep(cf) pra levar coisas junto
local function moveAv(av, hrp, target, speedFn, onStep)
    local y = hrp.Position.Y
    target = Vector3.new(target.X, y, target.Z)
    while alive() and av.Parent do
        if tripCancel then error("cancelado") end
        local dt = RunService.Heartbeat:Wait()
        local pos = hrp.Position
        local d = flat(target - pos)
        local dist = d.Magnitude
        if dist < 1 then break end
        local dir = d.Unit
        local np = pos + dir * math.min(dist, speedFn() * dt)
        if GK.speedMode ~= "Esteira" then GK.bolt(pos, np) end
        hrp.CFrame = CFrame.lookAt(np, np + dir)
        if onStep then onStep(hrp.CFrame) end
    end
end

-- monstro anda levando o avatar sentado nas costas
local function rideTo(ms, hrp, groundY, target, speedFn)
    local cur = ms.ridePos
    while alive() and ms.model.Parent do
        if tripCancel then error("cancelado") end
        local dt = RunService.Heartbeat:Wait()
        local d = flat(target - cur)
        local dist = d.Magnitude
        if dist < 1 then break end
        local dir = d.Unit
        local before = cur
        cur = cur + dir * math.min(dist, speedFn() * dt)
        if GK.speedMode ~= "Esteira" then GK.bolt(Vector3.new(before.X, groundY + 2, before.Z), Vector3.new(cur.X, groundY + 2, cur.Z)) end
        local rot = CFrame.lookAt(Vector3.zero, dir)
        local center = Vector3.new(cur.X, groundY + ms.size.Y / 2, cur.Z)
        ms.model:PivotTo(CFrame.new(center) * rot * ms.centerToPivot)
        hrp.CFrame = CFrame.new(center + Vector3.new(0, ms.size.Y / 2 + 1.5, 0)) * rot
    end
    ms.ridePos = cur
end

local function progressBar(adornee, seconds, text)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 160, 0, 34); bb.StudsOffset = Vector3.new(0, 4, 0)
    bb.AlwaysOnTop = true; bb.Adornee = adornee; bb.Parent = folder
    local bg = Instance.new("Frame", bb)
    bg.Size = UDim2.new(1, 0, 0, 12); bg.Position = UDim2.new(0, 0, 1, -12)
    bg.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    local fill = Instance.new("Frame", bg)
    fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
    local tl = Instance.new("TextLabel", bb)
    tl.Size = UDim2.new(1, 0, 0, 20); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.GothamBlack
    tl.TextScaled = true; tl.TextColor3 = Color3.new(1, 1, 1); tl.TextStrokeTransparency = 0.2; tl.Text = text
    local t0 = tick()
    while tick() - t0 < seconds do
        fill.Size = UDim2.new((tick() - t0) / seconds, 0, 1, 0)
        task.wait()
    end
    bb:Destroy()
end

-- ===== efeitos de corrida =====
local GHOST_PARTS
local function rainbowSeq()
    local k = {}
    for i = 0, 6 do
        table.insert(k, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
    end
    return ColorSequence.new(k)
end

local function shockwave(pos)
    local ring = Instance.new("Part")
    ring.Shape = Enum.PartType.Cylinder; ring.Material = Enum.Material.Neon
    ring.Color = Color3.fromRGB(120, 220, 255); ring.Anchored = true
    ring.CanCollide = false; ring.CanTouch = false; ring.CanQuery = false
    ring.Size = Vector3.new(0.4, 2, 2)
    ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
    ring.Parent = folder
    task.spawn(function()
        for i = 1, 20 do
            ring.Size = Vector3.new(0.4, 2 + i * 2.2, 2 + i * 2.2)
            ring.Transparency = i / 20
            task.wait(0.02)
        end
        ring:Destroy()
    end)
end

-- so as partes do corpo viram fantasma (acessorios/asas deixam pesado)
GHOST_PARTS = {
    Head = true, UpperTorso = true, LowerTorso = true, Torso = true,
    LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
    LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
    ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}
-- liga rastro arco-iris, faiscas, aura, fantasmas e zoom; devolve funcao pra desligar
local function startRunFx(av, hrp, speedFn)
    local a0 = Instance.new("Attachment", hrp); a0.Position = Vector3.new(0, 1.6, 0)
    local a1 = Instance.new("Attachment", hrp); a1.Position = Vector3.new(0, -2.2, 0)
    local tr = Instance.new("Trail")
    tr.Attachment0, tr.Attachment1 = a0, a1
    tr.Color = rainbowSeq(); tr.LightEmission = 1; tr.Lifetime = 0.45
    tr.Transparency = NumberSequence.new(0.1, 1); tr.FaceCamera = true
    tr.Parent = hrp
    local spark = Instance.new("ParticleEmitter")
    spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    spark.Color = rainbowSeq(); spark.LightEmission = 1; spark.Rate = 90
    spark.Lifetime = NumberRange.new(0.3, 0.6); spark.Speed = NumberRange.new(2, 6)
    spark.SpreadAngle = Vector2.new(180, 180)
    spark.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0)})
    spark.Parent = hrp
    local aura = Instance.new("ParticleEmitter")
    aura.Texture = "rbxasset://textures/particles/fire_main.dds"
    aura.Color = ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.fromRGB(200, 90, 255))
    aura.LightEmission = 1; aura.Rate = 45; aura.Lifetime = NumberRange.new(0.25, 0.45)
    aura.Speed = NumberRange.new(0.5, 2); aura.LockedToPart = true
    aura.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0)})
    aura.Transparency = NumberSequence.new(0.3, 1)
    aura.Parent = hrp
    local stuff = {a0, a1, tr, spark, aura}

    local on = true
    local baseFov = Camera.FieldOfView
    -- fantasmas neon (acima de 250 de velocidade) + zoom
    task.spawn(function()
        local hue = 0
        while on and av.Parent do
            local spd = speedFn()
            Camera.FieldOfView = baseFov + math.clamp(15 + (spd - 1600) / 600, 15, 35)
            if spd > 2500 then
                hue = (hue + 0.08) % 1
                local col = Color3.fromHSV(hue, 0.8, 1)
                for _, p in ipairs(av:GetChildren()) do
                    if p:IsA("BasePart") and GHOST_PARTS[p.Name] and p.Transparency < 1 then
                        local g = Instance.new("Part")
                        g.Size = p.Size; g.CFrame = p.CFrame; g.Anchored = true
                        g.CanCollide = false; g.CanTouch = false; g.CanQuery = false
                        g.Material = Enum.Material.Neon; g.Color = col; g.Transparency = 0.45
                        g.Parent = folder
                        task.delay(0.05, function()
                            for i = 1, 6 do g.Transparency = 0.45 + i * 0.09 task.wait(0.04) end
                            g:Destroy()
                        end)
                    end
                end
            end
            task.wait(0.12)
        end
        Camera.FieldOfView = baseFov
    end)
    return function()
        on = false
        for _, o in ipairs(stuff) do pcall(function() o:Destroy() end) end
    end
end

-- bracos esticados pra frente segurando o ovo (sobrescreve a animacao so nos ombros)
local function holdArms(av)
    local motors = {}
    for _, n in ipairs({"RightShoulder", "LeftShoulder", "Right Shoulder", "Left Shoulder"}) do
        local m = av:FindFirstChild(n, true)
        if m and m:IsA("Motor6D") then table.insert(motors, m) end
    end
    local conn = RunService.Stepped:Connect(function()
        for _, m in ipairs(motors) do
            if m.Name:find("Right") then
                m.Transform = CFrame.Angles(math.rad(80), 0, math.rad(15))
            else
                m.Transform = CFrame.Angles(math.rad(80), 0, math.rad(-15))
            end
        end
    end)
    return function() conn:Disconnect() end
end

-- ponto entre as maos (ou na frente do peito)
local function handsPoint(av, hrp)
    local r = av:FindFirstChild("RightHand") or av:FindFirstChild("Right Arm")
    local l = av:FindFirstChild("LeftHand") or av:FindFirstChild("Left Arm")
    if r and l then
        return (r.Position + l.Position) / 2 + hrp.CFrame.LookVector * 0.6
    end
    return (hrp.CFrame * CFrame.new(0, 0.6, -2)).Position
end

tripSteal = function()
    if tripBusy then return end
    if GK.stopRun then GK.stopRun() end
    tripCancel = false
    local my = myPlot()
    if not my then if simPopup then simPopup("Clique 'Minha base e aqui' primeiro") end return end
    if #spawned >= MAX_ITEMS then if simPopup then simPopup("Base cheia!") end return end
    -- escolha do ovo: o selecionado > ovo do pet escolhido > ovo na AREA do pet > area do pet vazia > qualquer
    local egg, eggPos, petAreaName = selectedEgg, nil, nil
    if not (egg and egg.Parent) then egg = nil end
    if not egg and chosenPet then
        egg = eggOfPet(chosenPet)
        if not egg then
            local src
            petAreaName, src = petArea(chosenPet)
            if simPopup and petAreaName then simPopup("📍 " .. chosenPet .. ": " .. petAreaName .. " (" .. tostring(src) .. ")") end
            if petAreaName then
                egg = eggInArea(petAreaName)
                if not egg then eggPos = areaPos(petAreaName) end
            end
        end
    end
    if not egg and not eggPos and chosenPet then
        -- area do pet desconhecida: usa a area do painel (ou Cosmic), nunca aleatoria
        petAreaName = (simArea ~= "Todas" and simArea) or "Cosmic"
        egg = eggInArea(petAreaName)
        if not egg then eggPos = areaPos(petAreaName) end
    end
    if not egg and not eggPos then
        local e = pickEgg()
        egg = e and e.m
    end
    if egg then eggPos = egg:GetPivot().Position end
    if not eggPos then if simPopup then simPopup("Nao achei a area desse pet") end return end
    local realRoot = root()
    local realHum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not realRoot or not realHum then return end

    tripBusy = true
    local info = egg and eggCat[egg.Name]
    local cat = chosenPet or (info and info.cat)
    local areaTxt = petAreaName or (info and info.area) or (egg and egg.Name:match("_([%a ]+):Slot_")) or "?"
    local frame = plotFrame(my)
    local deliver = (frame * CFrame.new(0, 0, 12)).Position     -- dentro do cercado
    local groundBase = frame.Position.Y - 0.5
    local groundNest = eggPos.Y

    local av, hum, hrp = makeAvatar()
    if not av then tripBusy = false return end
    local startCF = realRoot.CFrame
    hrp.CFrame = startCF
    local hiding = true
    task.spawn(function() while hiding do setRealHidden(true) task.wait(0.4) end end)
    Camera.CameraSubject = hum
    shockwave(Vector3.new(hrp.Position.X, hrp.Position.Y - 2.8, hrp.Position.Z))
    local stopFx = startRunFx(av, hrp, avSpeed)
    local stopArms
    local rideMonster   -- se cancelar montado, some com ele

    local ok, err = pcall(function()
        -- 1) vai ate o ovo
        if simPopup then simPopup("🏃 Indo roubar: " .. (cat or "Ovo") .. " em " .. areaTxt) end
        avPlay(hum, "run")
        local toEgg = flat(eggPos - hrp.Position)
        local stop = eggPos - (toEgg.Magnitude > 0 and toEgg.Unit * 3 or Vector3.zero)
        moveAv(av, hrp, stop, avSpeed)
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(eggPos.X, hrp.Position.Y, eggPos.Z))

        -- 2) pega
        avPlay(hum, "idle")
        progressBar(hrp, 1.2, "Roubando...")
        pcall(GK.guardChase, areaTxt, hrp)
        local carry = cloneVisual(eggModelFor(cat) or egg or GK.fallbackEgg(petAreaName))
            or cloneVisual(GK.fallbackEgg())
        if not carry then error("sem modelo de ovo pra " .. tostring(cat)) end
        for _, p in ipairs(carry:GetDescendants()) do
            if p:IsA("BasePart") and (p.Name == "Hitbox" or p.Name == "CustomBoundingBox") then p.Transparency = 1 end
        end
        carry.Name = "Visual_SimEgg"; carry.Parent = folder
        local cs = {model = carry, phase = 0, nextGoal = 0, still = true, animated = true, isEgg = true, k = 1}
        measure(cs); cs.origFoot = math.max(0.5, cs.size.X)
        if egg then hideModel(egg) end
        if selectHL then selectHL:Destroy(); selectHL = nil end
        selectedEgg = nil
        stopArms = holdArms(av)
        local function carryStep(cf)
            local c = handsPoint(av, hrp) + Vector3.new(0, 0.2, 0)
            carry:PivotTo(CFrame.new(c) * (cf - cf.Position) * cs.centerToPivot)
        end
        -- segue as maos todo frame (inclusive parado)
        local follow
        follow = RunService.RenderStepped:Connect(function()
            if not hrp.Parent then
                follow:Disconnect()
                if not table.find(spawned, cs) then carry:Destroy() end
                return
            end
            if carry.Parent and not cs.flying then carryStep(hrp.CFrame) end
        end)
        cs.stopFollow = function() follow:Disconnect() end
        carryStep(hrp.CFrame)

        -- 3) leva pra base
        if simPopup then simPopup("🥚 Roubou! Levando pra base") end
        avPlay(hum, "run")
        -- animacao de carregar ovo do proprio jogo; se nao carregar, fica com os bracos esticados
        if GK.anim(av, GK.ANIM_CARRY, 1, Enum.AnimationPriority.Movement) and stopArms then stopArms(); stopArms = nil end
        moveAv(av, hrp, deliver, avSpeed, carryStep)

        -- 4) entrega: leva o ovo ate o lugar dele no cercado e planta ali
        cs.carried = true
        rescale(cs, scale)
        table.insert(spawned, cs)
        layout()
        sim.stolen = sim.stolen + 1
        pcall(GK.redeem, cat, deliver)
        if cs.home then
            if simPopup then simPopup("🌱 Plantando o ovo no lugar dele") end
            local spot = cs.home.Position
            local toSpot = flat(spot - hrp.Position)
            local stand = spot - (toSpot.Magnitude > 0.1 and toSpot.Unit * (cs.size.X / 2 + 2.5) or Vector3.zero)
            moveAv(av, hrp, stand, avSpeed, carryStep)
            hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(spot.X, hrp.Position.Y, spot.Z))
        end
        if cs.stopFollow then cs.stopFollow() end
        if stopArms then stopArms(); stopArms = nil end
        avPlay(hum, "idle")
        if cs.home then
            local from, to = carry:GetPivot(), cs.home * cs.centerToPivot
            for i = 1, 10 do carry:PivotTo(from:Lerp(to, i / 10)) task.wait(0.02) end
            cs.pos = cs.home
        end
        cs.carried = false
        addTag(cs)
        task.spawn(chocar, cs, cat)
        task.wait(0.35)

        -- 5) volta pro ninho e monta no monstro pai
        local am = RS:FindFirstChild("AssetModels")
        local src = cat and GK.petSource(cat)
        if not src and am then
            local all = {}
            for _, m in ipairs(am:GetChildren()) do if m:IsA("Model") then table.insert(all, m) end end
            src = all[math.random(#all)]
        end
        if src then
            if simPopup then simPopup("🐉 Voltando pra pegar o pai: " .. src.Name) end
            avPlay(hum, "run")
            moveAv(av, hrp, eggPos, avSpeed)
            local mon = src:Clone()
            prep(mon); mon.Name = "Visual_" .. src.Name; mon.Parent = folder
            local ms = {model = mon, phase = math.random() * 10, nextGoal = 0, petName = src.Name}
            rideMonster = ms
            pcall(function() ms.k = mon:GetScale() end)
            ms.k = ms.k or 1
            measure(ms); ms.origFoot = math.max(0.5, ms.size.X / ms.k)
            rescale(ms, scale)
            ms.ridePos = Vector3.new(eggPos.X, 0, eggPos.Z)
            ms.animated = playAnim(mon, src.Name, ms)
            mon:PivotTo(CFrame.new(eggPos.X, groundNest + ms.size.Y / 2, eggPos.Z) * ms.centerToPivot)
            if simPopup then simPopup("🐉 Montou no " .. src.Name .. "!") end
            avPlay(hum, "sit")
            -- ja reserva o lugar dele no cercado e vai montado ate la
            ms.flying = true
            ms.income = incomeFor(src.Name) * 3
            table.insert(spawned, ms)
            layout()
            local target = ms.home and ms.home.Position or deliver
            rideTo(ms, hrp, groundNest, target, function() return avSpeed() * 1.3 end)

            -- 6) desce do monstro: ele fica no lugar dele gerando dinheiro (3x)
            if ms.home then
                ms.model:PivotTo(ms.home * ms.centerToPivot)
                ms.pos = ms.home
            end
            ms.flying = false
            rideMonster = nil
            pcall(addTag, ms)
            local here = ms.home and ms.home.Position or target
            hrp.CFrame = CFrame.new(Vector3.new(here.X, startCF.Position.Y, here.Z) + frame.RightVector * (ms.size.X / 2 + 4))
        end

        -- 7) volta pro personagem real
        avPlay(hum, "run")
        moveAv(av, hrp, startCF.Position, avSpeed)
    end)

    if stopArms then pcall(stopArms) end
    if rideMonster then
        rideMonster.flying = false
        if not table.find(spawned, rideMonster) then pcall(function() rideMonster.model:Destroy() end) end
    end
    pcall(stopFx)
    hiding = false
    setRealHidden(false)
    Camera.CameraSubject = realHum
    if av then av:Destroy() end
    tripBusy = false
    if not ok and simPopup and not tostring(err):find("cancelado") then simPopup("Erro: " .. tostring(err)) end
end

-- ===== Flash no SEU personagem: so efeito (a velocidade de verdade quem manda e o servidor) =====
do
    local last, boltFrom, ghostT, baseFov = nil, nil, 0, nil
    local hb2
    hb2 = RunService.Heartbeat:Connect(function(dt)
        if not alive() then hb2:Disconnect() return end
        local ch = LP.Character
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not GK.flashChar or tripBusy or not hrp or not hum then
            last, boltFrom = nil, nil
            if baseFov and not tripBusy then Camera.FieldOfView = baseFov; baseFov = nil end
            return
        end
        local pos = hrp.Position
        local spd = last and Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude / math.max(dt, 1e-3) or 0
        last = pos
        if hum.MoveDirection.Magnitude > 0.1 and spd > 4 then
            -- raio amarelo atras de voce
            local feet = pos - Vector3.new(0, 1.2, 0)
            boltFrom = boltFrom or feet
            if (feet - boltFrom).Magnitude > 6 then GK.bolt(boltFrom, feet); boltFrom = feet end
            -- fantasmas amarelos
            ghostT = ghostT + dt
            if ghostT > 0.09 then
                ghostT = 0
                for _, part in ipairs(ch:GetChildren()) do
                    if part:IsA("BasePart") and GHOST_PARTS[part.Name] and part.Transparency < 1 then
                        local g = Instance.new("Part")
                        g.Size = part.Size; g.CFrame = part.CFrame; g.Anchored = true
                        g.CanCollide = false; g.CanTouch = false; g.CanQuery = false
                        g.Material = Enum.Material.Neon; g.Color = Color3.fromRGB(255, 200, 40); g.Transparency = 0.5
                        g.Parent = folder
                        task.delay(0.03, function()
                            for i = 1, 5 do g.Transparency = 0.5 + i * 0.1 task.wait(0.03) end
                            g:Destroy()
                        end)
                    end
                end
            end
            -- pernas bem mais rapidas
            local an = hum:FindFirstChildOfClass("Animator")
            if an then
                for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
                    local n = tr.Name:lower()
                    if n:find("run") or n:find("walk") then tr:AdjustSpeed(3) end
                end
            end
            baseFov = baseFov or Camera.FieldOfView
            Camera.FieldOfView = Camera.FieldOfView + (baseFov + 18 - Camera.FieldOfView) * math.min(1, dt * 6)
        else
            boltFrom = nil
            if baseFov then
                Camera.FieldOfView = Camera.FieldOfView + (baseFov - Camera.FieldOfView) * math.min(1, dt * 6)
                if math.abs(Camera.FieldOfView - baseFov) < 0.3 then Camera.FieldOfView = baseFov; baseFov = nil end
            end
        end
    end)
end

-- ===== CORRER FLASH (so na sua tela) =====
-- Uma copia sua corre rapido, controlada pelo seu teclado/analogico; a camera segue ela.
-- O personagem real fica parado e invisivel SO pra voce (pros outros voce esta parado).
do
    local run
    function GK.ghosts(model, color)
        for _, part in ipairs(model:GetChildren()) do
            if part:IsA("BasePart") and GHOST_PARTS[part.Name] and part.Transparency < 1 then
                local g = Instance.new("Part")
                g.Size = part.Size; g.CFrame = part.CFrame; g.Anchored = true
                g.CanCollide = false; g.CanTouch = false; g.CanQuery = false
                g.Material = Enum.Material.Neon; g.Color = color; g.Transparency = 0.45
                g.Parent = folder
                task.delay(0.03, function()
                    for i = 1, 5 do g.Transparency = 0.45 + i * 0.11 task.wait(0.03) end
                    g:Destroy()
                end)
            end
        end
    end
    function GK.isRunning() return run ~= nil end
    function GK.stopRun()
        if not run then return end
        local r = run
        run = nil
        pcall(function() r.conn:Disconnect() end)
        setRealHidden(false)
        local ch = LP.Character
        local rh = ch and ch:FindFirstChild("HumanoidRootPart")
        if rh then rh.Anchored = false end
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then Camera.CameraSubject = hum end
        pcall(function() r.av:Destroy() end)
        Camera.FieldOfView = r.fov
    end
    function GK.startRun()
        if run or tripBusy then return end
        local ch = LP.Character
        local rh = ch and ch:FindFirstChild("HumanoidRootPart")
        local rhum = ch and ch:FindFirstChildOfClass("Humanoid")
        if not rh or not rhum then return end
        local av, hum, hrp = makeAvatar()
        if not av then return end
        local rp = RaycastParams.new()
        rp.FilterType = Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances = {folder, ch}
        local g = workspace:Raycast(rh.Position, Vector3.new(0, -50, 0), rp)
        local hip = g and (rh.Position.Y - g.Position.Y) or 3
        hrp.CFrame = rh.CFrame
        rh.Anchored = true                      -- o real fica parado onde estava
        local r = {av = av, fov = Camera.FieldOfView}
        run = r
        task.spawn(function()
            while run == r do setRealHidden(true) task.wait(0.4) end
        end)
        Camera.CameraSubject = hum
        avPlay(hum, "idle")
        local moving, boltFrom, ghostT = false, nil, 0
        r.conn = RunService.Heartbeat:Connect(function(dt)
            if run ~= r then return end
            if not alive() or not av.Parent or not rhum.Parent then GK.stopRun() return end
            -- direcao que voce aperta (teclado ou analogico): o jogo calcula no MoveDirection
            local dir = Vector3.new(rhum.MoveDirection.X, 0, rhum.MoveDirection.Z)
            local mv = dir.Magnitude > 0.1
            if mv ~= moving then
                moving = mv
                avPlay(hum, mv and "run" or "idle")
            end
            if mv then
                dir = dir.Unit
                local pp = hrp.Position + dir * GK.runSpeed * dt
                rp.FilterDescendantsInstances = {folder, LP.Character}
                local hit = workspace:Raycast(pp + Vector3.new(0, 30, 0), Vector3.new(0, -200, 0), rp)
                local np = Vector3.new(pp.X, hit and (hit.Position.Y + hip) or hrp.Position.Y, pp.Z)
                hrp.CFrame = CFrame.lookAt(np, np + dir)
                local feet = np - Vector3.new(0, hip - 0.3, 0)
                boltFrom = boltFrom or feet
                if (feet - boltFrom).Magnitude > 6 then GK.bolt(boltFrom, feet); boltFrom = feet end
                ghostT = ghostT + dt
                if ghostT > 0.06 then ghostT = 0; GK.ghosts(av, Color3.fromRGB(255, 200, 40)) end
                local an = hum:FindFirstChildOfClass("Animator")
                if an then
                    for _, tr in ipairs(an:GetPlayingAnimationTracks()) do tr:AdjustSpeed(math.clamp(GK.runSpeed / 60, 1.5, 4)) end
                end
                Camera.FieldOfView = Camera.FieldOfView + (r.fov + 22 - Camera.FieldOfView) * math.min(1, dt * 6)
            else
                boltFrom = nil
                Camera.FieldOfView = Camera.FieldOfView + (r.fov - Camera.FieldOfView) * math.min(1, dt * 6)
            end
        end)
    end
end

-- ===== SKINS (so na sua tela) =====
-- Rastro: copia o rastro do jogo (ReplicatedStorage.Assets.Trails) e prende no seu personagem.
-- Avatar: um "boneco" com a skin escolhida fica por cima de voce copiando cada movimento;
-- o seu personagem de verdade fica invisivel SO pra voce. Pros outros nada muda.
GK.TRAIL_ORDER = {"GreyTrail", "BlueTrail", "GreenTrail", "RedTrail", "PurpleTrail", "GoldenTrail",
    "GalaxyTrail", "SecretTrail", "EternalTrail", "DivineTrail", "MoonbloomTrail"}
GK.TRAIL_COLORS = {
    GreyTrail = {Color3.fromRGB(170, 170, 170), Color3.fromRGB(90, 90, 90)},
    BlueTrail = {Color3.fromRGB(60, 140, 255), Color3.fromRGB(20, 60, 200)},
    GreenTrail = {Color3.fromRGB(80, 255, 120), Color3.fromRGB(20, 150, 60)},
    RedTrail = {Color3.fromRGB(255, 70, 70), Color3.fromRGB(150, 10, 10)},
    PurpleTrail = {Color3.fromRGB(190, 90, 255), Color3.fromRGB(90, 20, 170)},
    GoldenTrail = {Color3.fromRGB(255, 220, 80), Color3.fromRGB(200, 130, 10)},
    SecretTrail = {Color3.fromRGB(40, 40, 40), Color3.fromRGB(255, 255, 255)},
    EternalTrail = {Color3.fromRGB(255, 250, 230), Color3.fromRGB(255, 200, 120)},
    DivineTrail = {Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 255, 255)},
}
function GK.trailNames()
    local out, seen = {}, {}
    local ok, f = pcall(function() return RS.Assets.Trails end)
    if not ok or not f then return out end
    for _, n in ipairs(GK.TRAIL_ORDER) do
        if f:FindFirstChild(n) then table.insert(out, n); seen[n] = true end
    end
    for _, c in ipairs(f:GetChildren()) do
        if not seen[c.Name] then table.insert(out, c.Name) end
    end
    return out
end
function GK.wearTrail(name)
    if GK.trailPart then pcall(function() GK.trailPart:Destroy() end) GK.trailPart = nil end
    GK.trailName = name
    local ch = LP.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if not name or not hrp then return false end
    local src
    pcall(function() src = RS.Assets.Trails[name] end)
    if not src then return false end
    local c = src:Clone()
    local parts = {}
    if c:IsA("BasePart") then table.insert(parts, c) end
    for _, d in ipairs(c:GetDescendants()) do if d:IsA("BasePart") then table.insert(parts, d) end end
    for _, p in ipairs(parts) do
        p.Anchored = false; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.Massless = true
    end
    local main = parts[1]
    if not main then c:Destroy() return false end
    main.CFrame = hrp.CFrame
    local w = main:FindFirstChildOfClass("WeldConstraint") or Instance.new("WeldConstraint", main)
    w.Part0, w.Part1 = main, hrp
    -- liga o efeito; se a peca vier sem o Trail dentro, monta um com as cores do nome
    local hasFx = false
    for _, d in ipairs(c:GetDescendants()) do
        if d:IsA("Trail") or d:IsA("ParticleEmitter") or d:IsA("Beam") then d.Enabled = true; hasFx = true end
    end
    if not hasFx then
        local a0 = main:FindFirstChild("MainTrailAttachment1") or Instance.new("Attachment", main)
        local a1 = main:FindFirstChild("MainTrailAttachment2")
        if not a1 then a1 = Instance.new("Attachment", main); a0.Position = Vector3.new(0, 1, 0); a1.Position = Vector3.new(0, -1, 0) end
        local tr = Instance.new("Trail")
        tr.Attachment0, tr.Attachment1 = a0, a1
        local col = GK.TRAIL_COLORS[name]
        if name == "GalaxyTrail" or not col then
            local k = {}
            for i = 0, 6 do table.insert(k, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.8, 1))) end
            tr.Color = ColorSequence.new(k)
        else
            tr.Color = ColorSequence.new(col[1], col[2])
        end
        tr.Lifetime = 0.6; tr.LightEmission = 0.6
        tr.Transparency = NumberSequence.new(0.1, 1)
        tr.Parent = main
    end
    c.Parent = folder
    GK.trailPart = c
    -- o rastro de verdade some (so pra voce)
    for _, d in ipairs(ch:GetDescendants()) do
        if d:IsA("Trail") then d.Enabled = false end
    end
    return true
end

do
    local skin
    local function motorsOf(m)
        local t = {}
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("Motor6D") then t[d.Name .. "|" .. (d.Parent and d.Parent.Name or "")] = d end
        end
        return t
    end
    function GK.hasSkin() return skin ~= nil end
    function GK.clearSkin()
        if not skin then return end
        local s0 = skin
        skin = nil
        GK.skinModel = nil
        pcall(function() s0.conn:Disconnect() end)
        pcall(function() s0.model:Destroy() end)
        setRealHidden(false)
    end
    -- veste uma copia de um modelo de personagem (de outro jogador ou criado pela descricao)
    function GK.wearModel(src)
        local ch = LP.Character
        if not ch or not ch:FindFirstChild("HumanoidRootPart") then return false, "sem personagem" end
        if not src then return false, "modelo vazio" end
        local old = src.Archivable
        src.Archivable = true
        local ok, m = pcall(function() return src:Clone() end)
        src.Archivable = old
        if not ok or not m then return false, "nao deu pra copiar" end
        GK.clearSkin()
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Tool")
                or d:IsA("ForceField") or d:IsA("BillboardGui") or d:IsA("Sound") then
                d:Destroy()
            elseif d:IsA("BasePart") then
                d.CanCollide = false; d.CanTouch = false; d.CanQuery = false; d.Massless = true; d.Anchored = false
            end
        end
        local hum = m:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.PlatformStand = true
            pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
            -- o Humanoid do boneco para de mexer na fisica (ele religava a colisao do corpo)
            pcall(function() hum.EvaluateStateMachine = false end)
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
        end
        local mparts = {}
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") then table.insert(mparts, d) end
        end
        local mroot = m:FindFirstChild("HumanoidRootPart")
        if not mroot then m:Destroy() return false, "modelo sem HumanoidRootPart" end
        mroot.Anchored = true
        mroot.Transparency = 1
        m.Name = "VisualSkin"
        m.Parent = folder
        local s0 = {model = m, theirs = motorsOf(m)}
        skin = s0
        GK.skinModel = m
        local acc, hidden = 0, nil
        s0.conn = RunService.Heartbeat:Connect(function(dt)
            if skin ~= s0 then return end
            local c = LP.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not r or not m.Parent then return end
            if c ~= s0.char then s0.char = c; s0.mine = motorsOf(c) end
            -- nada do boneco pode encostar em voce (senao te arremessa)
            for _, bp in ipairs(mparts) do
                if bp.CanCollide then bp.CanCollide = false end
                if bp.CanTouch then bp.CanTouch = false end
            end
            -- copia posicao e a pose (cada junta) do seu personagem
            mroot.CFrame = r.CFrame
            for key, mm in pairs(s0.theirs) do
                local rm = s0.mine[key]
                if rm then mm.Transform = rm.Transform end
            end
            acc = acc + dt
            if acc > 0.3 then
                acc = 0
                setRealHidden(true)
                -- durante o roubo / Correr Flash a copia que corre ja usa a skin: esconde esta
                local away = tripBusy or (GK.isRunning and GK.isRunning())
                if away ~= hidden then
                    hidden = away
                    for _, d in ipairs(m:GetDescendants()) do
                        if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = away and 1 or 0 end
                    end
                end
            end
        end)
        return true
    end
end
function GK.wearDescription(desc)
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    if not hum then return false, "sem personagem" end
    local ok, m = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, hum.RigType) end)
    if not ok or not m then return false, "o Roblox nao deixou montar o avatar: " .. tostring(m) end
    local r1, r2 = GK.wearModel(m)
    pcall(function() m:Destroy() end)
    return r1, r2
end
function GK.baseDesc()
    if GK.curDesc then return GK.curDesc end
    local ok, d = pcall(function() return Players:GetHumanoidDescriptionFromUserId(LP.UserId) end)
    if ok and d then GK.curDesc = d return d end
    local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
    local ok2, d2 = pcall(function() return hum:GetAppliedDescription() end)
    if ok2 and d2 then GK.curDesc = d2 return d2 end
end
-- itens raros famosos (ids do catalogo do Roblox)
GK.PRESETS = {
    {"💀 Headless + Korblox", function(d) d.Head = 134082579; d.RightLeg = 139607718 end},
    {"👑 Dominus Empyreus", function(d) d.HatAccessory = "21070012" end},
    {"⚔️ Valkyrie Helm", function(d) d.HatAccessory = "1365767" end},
    {"🎩 Sparkle Time Fedora", function(d) d.HatAccessory = "1285307" end},
    {"👑 Domino Crown", function(d) d.HatAccessory = "1031429" end},
    {"🎧 Clockwork's Shades", function(d) d.FaceAccessory = "11748356" end},
}
function GK.wearPreset(i)
    local d = GK.baseDesc()
    if not d then return false, "nao consegui ler seu avatar" end
    GK.PRESETS[i][2](d)
    return GK.wearDescription(d)
end
-- tipo do item (catalogo) -> campo da descricao
GK.ITEM_FIELD = {
    [8] = "HatAccessory", [41] = "HairAccessory", [42] = "FaceAccessory", [43] = "NeckAccessory",
    [44] = "ShouldersAccessory", [45] = "FrontAccessory", [46] = "BackAccessory", [47] = "WaistAccessory",
    [17] = "Head", [18] = "Face", [11] = "Shirt", [12] = "Pants", [2] = "GraphicTShirt",
    [27] = "Torso", [28] = "RightArm", [29] = "LeftArm", [30] = "LeftLeg", [31] = "RightLeg",
}
function GK.wearItem(text)
    local id = tonumber((tostring(text or ""):match("%d+")))
    if not id then return false, "digite o numero (ID) do item" end
    local ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfo(id) end)
    if not ok or type(info) ~= "table" then return false, "item nao encontrado" end
    local field = GK.ITEM_FIELD[info.AssetTypeId]
    if not field then return false, "esse tipo de item ainda nao da (tipo " .. tostring(info.AssetTypeId) .. ")" end
    local d = GK.baseDesc()
    if not d then return false, "nao consegui ler seu avatar" end
    if field:find("Accessory") then
        local cur = d[field]
        d[field] = (cur ~= "" and (cur .. ",") or "") .. id
    else
        d[field] = id
    end
    local r1, r2 = GK.wearDescription(d)
    return r1, r1 and info.Name or r2
end
-- copia o avatar de alguem: jogador do servidor (instantaneo) ou qualquer nome/ID do Roblox
function GK.wearUser(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text == "" then return false, "digite um nome ou ID" end
    local id = tonumber(text)
    if not id then
        for _, p in ipairs(Players:GetPlayers()) do
            if (p.Name:lower() == text:lower() or p.DisplayName:lower() == text:lower()) and p.Character then
                GK.curDesc = nil
                return GK.wearModel(p.Character)
            end
        end
        local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(text) end)
        if not ok or not uid then return false, "usuario nao encontrado" end
        id = uid
    end
    local ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(id) end)
    if not ok or not desc then return false, "nao achei o avatar desse usuario" end
    GK.curDesc = desc
    return GK.wearDescription(desc)
end
function GK.resetLook()
    GK.curDesc = nil
    GK.clearSkin()
end
-- renasceu: recoloca rastro (a skin segue sozinha)
LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    if alive() and GK.trailName then pcall(GK.wearTrail, GK.trailName) end
end)

-- ================= LISTAS =================
local function petNames()
    local out = {}
    local am = RS:FindFirstChild("AssetModels")
    if am then for _, m in ipairs(am:GetChildren()) do if m:IsA("Model") then table.insert(out, m.Name) end end end
    table.sort(out)
    return out
end

local function nearestEgg()
    local r = root(); local f = workspace:FindFirstChild("AreaEggSlotsClient")
    if not r or not f then return end
    local best, bd
    for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") then
            local d = (m:GetPivot().Position - r.Position).Magnitude
            if not bd or d < bd then best, bd = m, d end
        end
    end
    return best
end

-- ================= GUI: 99NS22 HUB =================
-- (dentro de uma funcao: o Roblox so aceita 200 variaveis locais por funcao)
local function buildHub()
local TS  = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local VERSION = "v33"
local pickResp

if getgenv then
    for _, k in ipairs({"ModVipVisual", "ModVipSimGui", "NS22Hub"}) do
        if getgenv()[k] then pcall(function() getgenv()[k]:Destroy() end) end
    end
end

local hub = Instance.new("ScreenGui")
hub.Name = "NS22Hub"; hub.ResetOnSpawn = false; hub.DisplayOrder = 50
hub.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hub.Parent = (gethui and gethui()) or game:GetService("CoreGui")
if getgenv then getgenv().NS22Hub = hub; getgenv().ModVipVisual = hub end
local sg = hub   -- compat

-- sons sutis (clique e notificacao)
local SoundService = game:GetService("SoundService")
for _, n in ipairs({"NS22Click", "NS22Toast"}) do
    local old = SoundService:FindFirstChild(n); if old then old:Destroy() end
end
local clickSnd = Instance.new("Sound")
clickSnd.Name = "NS22Click"; clickSnd.SoundId = "rbxasset://sounds/electronicpingshort.wav"
clickSnd.Volume = 0.18; clickSnd.PlaybackSpeed = 1.8; clickSnd.Parent = SoundService
local toastSnd = Instance.new("Sound")
toastSnd.Name = "NS22Toast"; toastSnd.SoundId = "rbxasset://sounds/electronicpingshort.wav"
toastSnd.Volume = 0.25; toastSnd.PlaybackSpeed = 1.1; toastSnd.Parent = SoundService
local function playSnd(snd) pcall(function() snd.TimePosition = 0; snd:Play() end) end

-- ---------- tema ----------
local TH = {
    bg = Color3.fromRGB(12, 12, 22), panel = Color3.fromRGB(20, 20, 34), card = Color3.fromRGB(28, 28, 46),
    card2 = Color3.fromRGB(38, 38, 62), text = Color3.fromRGB(236, 236, 255), sub = Color3.fromRGB(150, 150, 190),
    a1 = Color3.fromRGB(0, 229, 255), a2 = Color3.fromRGB(168, 85, 247), a3 = Color3.fromRGB(255, 60, 172),
    ok = Color3.fromRGB(46, 204, 113), bad = Color3.fromRGB(239, 68, 68), gold = Color3.fromRGB(255, 196, 0),
}
local FT, FB, FN = Enum.Font.GothamBlack, Enum.Font.GothamBold, Enum.Font.Gotham

local spinGrads = {}
local function neonSeq()
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0, TH.a1), ColorSequenceKeypoint.new(0.5, TH.a2), ColorSequenceKeypoint.new(1, TH.a3),
    })
end
local function grad(parent, spin, rot)
    local g = Instance.new("UIGradient")
    g.Color = neonSeq(); g.Rotation = rot or 0; g.Parent = parent
    if spin then table.insert(spinGrads, g) end
    return g
end
local function corner(o, r)
    local c = Instance.new("UICorner"); c.CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0); c.Parent = o
    return c
end
local function stroke(o, th, spin, transp)
    local s = Instance.new("UIStroke")
    s.Thickness = th or 1.5; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color = Color3.new(1, 1, 1); s.Transparency = transp or 0; s.Parent = o
    grad(s, spin)
    return s
end
local function tween(o, t, props, style)
    local tw = TS:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
    tw:Play(); return tw
end
local function label(parent, text, size, font, color)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1; t.Text = text or ""; t.TextSize = size or 14
    t.Font = font or FB; t.TextColor3 = color or TH.text; t.Parent = parent
    return t
end

-- bordas neon girando
local spinConn
spinConn = RunService.Heartbeat:Connect(function(dt)
    if not alive() then spinConn:Disconnect() return end
    for _, g in ipairs(spinGrads) do g.Rotation = (g.Rotation + dt * 70) % 360 end
end)

-- ---------- botao redondo flutuante ----------
local orbHolder = Instance.new("Frame", hub)
orbHolder.Size = UDim2.fromOffset(86, 86); orbHolder.Position = UDim2.new(0, 22, 0.5, -43)
orbHolder.BackgroundTransparency = 1

local orb   -- criado logo abaixo (a aura usa o tamanho dele)
local glow = Instance.new("Frame", orbHolder)
glow.AnchorPoint = Vector2.new(0.5, 0.5); glow.Position = UDim2.fromScale(0.5, 0.5)
glow.Size = UDim2.fromOffset(86, 86); glow.BackgroundColor3 = Color3.new(1, 1, 1); glow.BackgroundTransparency = 0.75
corner(glow); grad(glow, true, 45)
task.spawn(function()
    while alive() and glow.Parent do
        local o = orb and orb.Size.X.Offset or 78
        tween(glow, 1.1, {Size = UDim2.fromOffset(o + 26, o + 26), BackgroundTransparency = 0.92}, Enum.EasingStyle.Sine)
        task.wait(1.1)
        tween(glow, 1.1, {Size = UDim2.fromOffset(o + 8, o + 8), BackgroundTransparency = 0.75}, Enum.EasingStyle.Sine)
        task.wait(1.1)
    end
end)

orb = Instance.new("TextButton", orbHolder)
orb.AnchorPoint = Vector2.new(0.5, 0.5); orb.Position = UDim2.fromScale(0.5, 0.5)
orb.Size = UDim2.fromOffset(78, 78); orb.BackgroundColor3 = TH.bg; orb.Text = ""; orb.AutoButtonColor = false
corner(orb); stroke(orb, 3.5, true)
local orbScale = Instance.new("UIScale", orb)
local orbIn = Instance.new("Frame", orb)
orbIn.AnchorPoint = Vector2.new(0.5, 0.5); orbIn.Position = UDim2.fromScale(0.5, 0.5)
orbIn.Size = UDim2.new(1, -12, 1, -12); orbIn.BackgroundColor3 = Color3.new(1, 1, 1); orbIn.BackgroundTransparency = 0.82
corner(orbIn); grad(orbIn, false, 90)
local orbName = label(orb, "99NS22", 18, FT, Color3.new(1, 1, 1))
orbName.AnchorPoint = Vector2.new(0.5, 0.5); orbName.Position = UDim2.new(0.5, 0, 0.44, 0)
orbName.Size = UDim2.new(0.84, 0, 0.3, 0); orbName.TextScaled = true
grad(orbName, true)
local orbSub = label(orb, "HUB", 11, FT, TH.sub)
orbSub.AnchorPoint = Vector2.new(0.5, 0.5); orbSub.Position = UDim2.new(0.5, 0, 0.7, 0)
orbSub.Size = UDim2.new(0.6, 0, 0.16, 0); orbSub.TextScaled = true

orbScale.Scale = 0
task.delay(0.2, function() tween(orbScale, 0.6, {Scale = 1}, Enum.EasingStyle.Back) end)
orb.MouseEnter:Connect(function() tween(orbScale, 0.2, {Scale = 1.08}) end)
orb.MouseLeave:Connect(function() tween(orbScale, 0.2, {Scale = 1}) end)

-- arrastar o botao (clique sem arrastar = abre/fecha)
local function makeDraggable(handle, target, onClick)
    local dragging, moved, startPos, startInput = false, false, nil, nil
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, moved, startInput, startPos = true, false, i.Position, target.Position
            local c
            c = i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then
                    dragging = false; c:Disconnect()
                    if not moved and onClick then onClick() end
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            if d.Magnitude > 5 then moved = true end
            if moved then
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
end

-- ---------- janela principal ----------
local WW, WH = 640, 420
local winBox = Instance.new("Frame", hub)
winBox.AnchorPoint = Vector2.new(0.5, 0.5); winBox.Position = UDim2.fromScale(0.5, 0.5)
winBox.Size = UDim2.fromOffset(WW, WH); winBox.BackgroundTransparency = 1
local respScale = Instance.new("UIScale", winBox)
local win = Instance.new("Frame", winBox)
win.AnchorPoint = Vector2.new(0.5, 0.5); win.Position = UDim2.fromScale(0.5, 0.5)
win.Size = UDim2.fromScale(1, 1); win.BackgroundColor3 = TH.bg; win.BackgroundTransparency = 0.03
win.Visible = false; win.Active = true
corner(win, 18); stroke(win, 2, true)
local winScale = Instance.new("UIScale", win)

-- fundo com brilho sutil
local shine = Instance.new("Frame", win)
shine.Size = UDim2.new(1, 0, 0, 120); shine.BackgroundColor3 = Color3.new(1, 1, 1); shine.BackgroundTransparency = 0.94
shine.BorderSizePixel = 0; corner(shine, 18)
local sg2 = grad(shine, false, 0)
sg2.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})
sg2.Rotation = 90

-- header
local header = Instance.new("Frame", win)
header.Size = UDim2.new(1, 0, 0, 56); header.BackgroundTransparency = 1
local hTitle = label(header, "99NS22", 26, FT, Color3.new(1, 1, 1))
hTitle.Position = UDim2.fromOffset(20, 8); hTitle.Size = UDim2.fromOffset(130, 40)
hTitle.TextXAlignment = Enum.TextXAlignment.Left; grad(hTitle, true)
local hHub = label(header, "HUB", 26, FT, TH.text)
hHub.Position = UDim2.fromOffset(140, 8); hHub.Size = UDim2.fromOffset(70, 40); hHub.TextXAlignment = Enum.TextXAlignment.Left
local chip = Instance.new("Frame", header)
chip.Position = UDim2.fromOffset(212, 18); chip.Size = UDim2.fromOffset(112, 22); chip.BackgroundColor3 = TH.card
corner(chip, 11); stroke(chip, 1, true, 0.3)
local chipT = label(chip, VERSION, 11, FT, TH.text); chipT.Size = UDim2.fromScale(1, 1)

local hStats = label(header, "", 13, FT, TH.text)
hStats.AnchorPoint = Vector2.new(1, 0); hStats.Position = UDim2.new(1, -56, 0, 14)
hStats.Size = UDim2.fromOffset(230, 30); hStats.TextXAlignment = Enum.TextXAlignment.Right
local closeB = Instance.new("TextButton", header)
closeB.AnchorPoint = Vector2.new(1, 0); closeB.Position = UDim2.new(1, -16, 0, 14)
closeB.Size = UDim2.fromOffset(30, 30); closeB.BackgroundColor3 = TH.card; closeB.Text = "✕"
closeB.TextColor3 = TH.text; closeB.Font = FT; closeB.TextSize = 14; closeB.AutoButtonColor = false
corner(closeB, 9)
closeB.MouseEnter:Connect(function() tween(closeB, 0.15, {BackgroundColor3 = TH.bad}) end)
closeB.MouseLeave:Connect(function() tween(closeB, 0.15, {BackgroundColor3 = TH.card}) end)

-- sidebar
local side = Instance.new("Frame", win)
side.Position = UDim2.fromOffset(14, 62); side.Size = UDim2.new(0, 150, 1, -110)
side.BackgroundColor3 = TH.panel; corner(side, 14)
local sideList = Instance.new("UIListLayout", side); sideList.Padding = UDim.new(0, 6)
sideList.SortOrder = Enum.SortOrder.LayoutOrder
local sidePad = Instance.new("UIPadding", side)
sidePad.PaddingTop = UDim.new(0, 8); sidePad.PaddingLeft = UDim.new(0, 8); sidePad.PaddingRight = UDim.new(0, 8)

-- area das paginas
local pagesHolder = Instance.new("Frame", win)
pagesHolder.Position = UDim2.fromOffset(176, 62); pagesHolder.Size = UDim2.new(1, -190, 1, -110)
pagesHolder.BackgroundTransparency = 1; pagesHolder.ClipsDescendants = true

-- barra de status
local statusBar = Instance.new("Frame", win)
statusBar.Position = UDim2.new(0, 14, 1, -40); statusBar.Size = UDim2.new(1, -28, 0, 28)
statusBar.BackgroundColor3 = TH.panel; corner(statusBar, 10)
local dot = Instance.new("Frame", statusBar)
dot.Position = UDim2.new(0, 10, 0.5, -4); dot.Size = UDim2.fromOffset(8, 8); dot.BackgroundColor3 = TH.ok; corner(dot)
statusLabel = label(statusBar, "Pronto", 12, FB, TH.sub)
statusLabel.Position = UDim2.fromOffset(26, 0); statusLabel.Size = UDim2.new(1, -36, 1, 0)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left; statusLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- arrastar a janela pelo header
makeDraggable(header, winBox)

-- abrir / fechar com animacao
local winOpen = false
local function setWin(open)
    winOpen = open
    if open then
        win.Visible = true; winScale.Scale = 0.85
        tween(winScale, 0.35, {Scale = 1}, Enum.EasingStyle.Back)
    else
        tween(winScale, 0.18, {Scale = 0.85})
        task.delay(0.18, function() if not winOpen then win.Visible = false end end)
    end
end
makeDraggable(orb, orbHolder, function() setWin(not winOpen) end)
closeB.MouseButton1Click:Connect(function() setWin(false) end)
UIS.InputBegan:Connect(function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.RightShift and alive() then setWin(not winOpen) end
end)

-- ---------- componentes ----------
local pages, tabs = {}, {}
local function selectTab(name)
    for n, t in pairs(tabs) do
        local on = (n == name)
        if on and not pages[n].Visible then
            pages[n].Position = UDim2.fromOffset(0, 14)
            tween(pages[n], 0.3, {Position = UDim2.new()})
        end
        pages[n].Visible = on
        t.bar.Visible = on
        t.tx.TextColor3 = on and TH.text or TH.sub
        t.btn.BackgroundColor3 = on and TH.card2 or TH.panel
        t.grad.Transparency = on and NumberSequence.new({NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1)}) or NumberSequence.new(1)
    end
end
local function newPage(name, icon, order)
    local pg = Instance.new("ScrollingFrame", pagesHolder)
    pg.Size = UDim2.fromScale(1, 1); pg.BackgroundTransparency = 1; pg.BorderSizePixel = 0
    pg.ScrollBarThickness = 3; pg.ScrollBarImageColor3 = TH.a2
    pg.AutomaticCanvasSize = Enum.AutomaticSize.Y; pg.CanvasSize = UDim2.new(); pg.Visible = false
    local l = Instance.new("UIListLayout", pg); l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder
    local pd = Instance.new("UIPadding", pg); pd.PaddingRight = UDim.new(0, 8); pd.PaddingBottom = UDim.new(0, 8)
    pg:SetAttribute("n", 0)

    local tb = Instance.new("TextButton", side)
    tb.Size = UDim2.new(1, 0, 0, 40); tb.BackgroundColor3 = TH.panel; tb.AutoButtonColor = false
    tb.Text = ""; tb.LayoutOrder = order; corner(tb, 10)
    local bar = Instance.new("Frame", tb)
    bar.Size = UDim2.new(0, 4, 0.6, 0); bar.Position = UDim2.new(0, 0, 0.2, 0); bar.BackgroundColor3 = Color3.new(1, 1, 1)
    bar.Visible = false; corner(bar, 2); grad(bar, false, 90)
    local ic = label(tb, icon, 18, FT); ic.Position = UDim2.fromOffset(10, 0); ic.Size = UDim2.new(0, 26, 1, 0)
    local tx = label(tb, name, 14, FB, TH.sub); tx.Position = UDim2.fromOffset(42, 0); tx.Size = UDim2.new(1, -46, 1, 0)
    tx.TextXAlignment = Enum.TextXAlignment.Left
    local bgGrad = grad(tb, false, 0)
    bgGrad.Transparency = NumberSequence.new(1)
    tabs[name] = {btn = tb, bar = bar, tx = tx, grad = bgGrad}
    pages[name] = pg
    tb.MouseEnter:Connect(function() if not pg.Visible then tween(tb, 0.15, {BackgroundColor3 = TH.card}) end end)
    tb.MouseLeave:Connect(function() if not pg.Visible then tween(tb, 0.15, {BackgroundColor3 = TH.panel}) end end)
    tb.MouseButton1Click:Connect(function() selectTab(name) end)
    return pg
end
local function nextOrder(pg) local n = pg:GetAttribute("n") + 1; pg:SetAttribute("n", n); return n end

local function section(pg, text)
    local t = label(pg, string.upper(text), 11, FT, TH.sub)
    t.Size = UDim2.new(1, 0, 0, 18); t.TextXAlignment = Enum.TextXAlignment.Left; t.LayoutOrder = nextOrder(pg)
    local line = Instance.new("Frame", t)
    line.AnchorPoint = Vector2.new(0, 0.5); line.Position = UDim2.new(0, t.TextBounds.X + 140, 0.5, 0)
    line.Size = UDim2.new(1, -(t.TextBounds.X + 140), 0, 1); line.BackgroundColor3 = Color3.new(1, 1, 1)
    line.BackgroundTransparency = 0.6; line.BorderSizePixel = 0; grad(line)
    task.defer(function() line.Position = UDim2.new(0, t.TextBounds.X + 8, 0.5, 0); line.Size = UDim2.new(1, -(t.TextBounds.X + 8), 0, 1) end)
    return t
end

-- estilos: "main" (neon), "ok", "bad", "gold", "card"
local function styleBtn(b, style)
    b.BackgroundColor3 = TH.card
    for _, c in ipairs(b:GetChildren()) do if c:IsA("UIGradient") then c:Destroy() end end
    if style == "main" then
        -- degrade so de claro/escuro: um degrade colorido pintava o TEXTO da mesma cor do fundo (sumia)
        b.BackgroundColor3 = Color3.fromRGB(140, 60, 240)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
        g.Rotation = 90; g.Parent = b
        b.TextStrokeTransparency = 0.35
    elseif style == "ok" then b.BackgroundColor3 = Color3.fromRGB(30, 150, 90)
    elseif style == "bad" then b.BackgroundColor3 = Color3.fromRGB(170, 40, 60)
    elseif style == "gold" then b.BackgroundColor3 = Color3.fromRGB(200, 140, 20)
    end
end

local function mkBtn(parent, text, style, cb)
    local b = Instance.new("TextButton", parent)
    b.Size = UDim2.new(1, 0, 0, 40); b.AutoButtonColor = false; b.Text = text
    b.Font = FB; b.TextSize = 14; b.TextColor3 = Color3.new(1, 1, 1)
    b.TextStrokeTransparency = 0.7
    corner(b, 10); styleBtn(b, style)
    local st = Instance.new("UIStroke", b); st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st.Color = Color3.new(1, 1, 1); st.Transparency = 0.9; st.Thickness = 1
    local sc = Instance.new("UIScale", b)
    b.MouseEnter:Connect(function() tween(st, 0.15, {Transparency = 0.4}); tween(sc, 0.15, {Scale = 1.02}) end)
    b.MouseLeave:Connect(function() tween(st, 0.15, {Transparency = 0.9}); tween(sc, 0.15, {Scale = 1}) end)
    b.MouseButton1Down:Connect(function() tween(sc, 0.08, {Scale = 0.96}) end)
    b.MouseButton1Up:Connect(function() tween(sc, 0.15, {Scale = 1.02}, Enum.EasingStyle.Back) end)
    b.MouseButton1Click:Connect(function() playSnd(clickSnd); task.spawn(function() pcall(cb, b) end) end)
    return b
end

local function button(pg, text, style, cb)
    local b = mkBtn(pg, text, style, cb); b.LayoutOrder = nextOrder(pg); return b
end

-- linha com varios botoes lado a lado: {{texto, estilo, cb}, ...}
local function row(pg, items, h)
    local fr = Instance.new("Frame", pg)
    fr.Size = UDim2.new(1, 0, 0, h or 40); fr.BackgroundTransparency = 1; fr.LayoutOrder = nextOrder(pg)
    local l = Instance.new("UIListLayout", fr); l.FillDirection = Enum.FillDirection.Horizontal
    l.Padding = UDim.new(0, 8); l.SortOrder = Enum.SortOrder.LayoutOrder
    local out = {}
    local n = #items
    for i, it in ipairs(items) do
        local b = mkBtn(fr, it[1], it[2], it[3])
        b.Size = UDim2.new(1 / n, -(8 * (n - 1)) / n, 1, 0); b.LayoutOrder = i
        out[i] = b
    end
    return out
end

-- interruptor estilo pilula
local function toggle(pg, text, get, set)
    local fr = Instance.new("TextButton", pg)
    fr.Size = UDim2.new(1, 0, 0, 44); fr.BackgroundColor3 = TH.card; fr.AutoButtonColor = false; fr.Text = ""
    fr.LayoutOrder = nextOrder(pg); corner(fr, 10)
    local t = label(fr, text, 14, FB); t.Position = UDim2.fromOffset(14, 0); t.Size = UDim2.new(1, -80, 1, 0)
    t.TextXAlignment = Enum.TextXAlignment.Left
    local sw = Instance.new("Frame", fr)
    sw.AnchorPoint = Vector2.new(1, 0.5); sw.Position = UDim2.new(1, -12, 0.5, 0); sw.Size = UDim2.fromOffset(48, 24)
    sw.BackgroundColor3 = TH.card2; corner(sw)
    local swg = grad(sw, false, 0)
    local knob = Instance.new("Frame", sw)
    knob.AnchorPoint = Vector2.new(0, 0.5); knob.Size = UDim2.fromOffset(18, 18); knob.BackgroundColor3 = Color3.new(1, 1, 1)
    corner(knob)
    local function paint(anim)
        local on = get()
        local t0 = anim and 0.2 or 0
        swg.Enabled = on
        sw.BackgroundColor3 = on and Color3.new(1, 1, 1) or TH.card2
        tween(knob, t0, {Position = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)})
    end
    fr.MouseButton1Click:Connect(function() playSnd(clickSnd); set(not get()); paint(true) end)
    paint(false)
    return function() paint(true) end
end

-- seletor que alterna valores ao clicar
local function cycle(pg, text, getText, onClick)
    local fr = Instance.new("TextButton", pg)
    fr.Size = UDim2.new(1, 0, 0, 44); fr.BackgroundColor3 = TH.card; fr.AutoButtonColor = false; fr.Text = ""
    fr.LayoutOrder = nextOrder(pg); corner(fr, 10)
    local t = label(fr, text, 14, FB); t.Position = UDim2.fromOffset(14, 0); t.Size = UDim2.new(0.5, 0, 1, 0)
    t.TextXAlignment = Enum.TextXAlignment.Left
    local v = Instance.new("Frame", fr)
    v.AnchorPoint = Vector2.new(1, 0.5); v.Position = UDim2.new(1, -10, 0.5, 0); v.Size = UDim2.fromOffset(150, 28)
    v.BackgroundColor3 = TH.card2; corner(v, 8); stroke(v, 1, true, 0.4)
    local vt = label(v, "", 13, FT); vt.Size = UDim2.fromScale(1, 1)
    local function paint() vt.Text = "◀  " .. getText() .. "  ▶" end
    fr.MouseButton1Click:Connect(function() playSnd(clickSnd); onClick(); paint() end)
    paint()
    return paint
end

local function note(pg, text)
    local t = label(pg, text, 12, FN, TH.sub)
    t.Size = UDim2.new(1, 0, 0, 30); t.TextWrapped = true; t.TextXAlignment = Enum.TextXAlignment.Left
    t.LayoutOrder = nextOrder(pg)
    return t
end

local function statCard(parent, icon, title, color)
    local c = Instance.new("Frame", parent)
    c.BackgroundColor3 = TH.card; corner(c, 12); stroke(c, 1, false, 0.7)
    local i = label(c, icon, 26, FT); i.Position = UDim2.fromOffset(12, 10); i.Size = UDim2.fromOffset(34, 34)
    local tt = label(c, string.upper(title), 10, FT, TH.sub); tt.Position = UDim2.fromOffset(54, 10)
    tt.Size = UDim2.new(1, -60, 0, 14); tt.TextXAlignment = Enum.TextXAlignment.Left
    local v = label(c, "0", 22, FT, color or TH.text); v.Position = UDim2.fromOffset(54, 24)
    v.Size = UDim2.new(1, -60, 0, 28); v.TextXAlignment = Enum.TextXAlignment.Left; v.TextScaled = true
    return v
end

-- miniatura 3D de um modelo (ViewportFrame)
local function makeThumb(parent, src)
    local vf = Instance.new("ViewportFrame")
    vf.Size = UDim2.new(1, -8, 1, -26); vf.Position = UDim2.fromOffset(4, 4); vf.BackgroundColor3 = TH.card2
    vf.Ambient = Color3.fromRGB(200, 200, 210); vf.LightColor = Color3.new(1, 1, 1)
    vf.LightDirection = Vector3.new(-1, -1, -1); vf.Active = false
    corner(vf, 8)
    vf.Parent = parent
    task.spawn(function()
        local ok, m = pcall(function() return src:Clone() end)
        if not ok or not m then return end
        local hide = {HumanoidRootPart = true, CenterCFrame = true, CENTER = true, Hitbox = true, CustomBoundingBox = true, RootPart = true}
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
                d:Destroy()
            elseif d:IsA("BasePart") and hide[d.Name] then
                d.Transparency = 1
            end
        end
        if not m:IsA("Model") then local w = Instance.new("Model"); m.Parent = w; m = w end
        m.Parent = vf
        local center, size = visualBox(m)
        local r = math.max(size.X, size.Y, size.Z, 1)
        local cam = Instance.new("Camera")
        cam.FieldOfView = 40
        cam.CFrame = CFrame.lookAt(center + Vector3.new(r * 0.85, r * 0.45, -r * 0.85), center)
        cam.Parent = vf
        vf.CurrentCamera = cam
    end)
    return vf
end

local function thumbCell(parent, src, caption, order)
    local b = Instance.new("TextButton", parent)
    b.Text = ""; b.AutoButtonColor = false; b.LayoutOrder = order; b.BackgroundColor3 = TH.card
    corner(b, 10)
    local st = Instance.new("UIStroke", b); st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    st.Thickness = 2; st.Color = Color3.new(1, 1, 1); st.Transparency = 1
    local sg3 = grad(st, true)
    if src then makeThumb(b, src) end
    local tl = label(b, caption, 12, FB); tl.Size = UDim2.new(1, -6, 0, 20); tl.Position = UDim2.new(0, 3, 1, -21)
    tl.TextScaled = true
    local sc = Instance.new("UIScale", b)
    b.MouseEnter:Connect(function() tween(sc, 0.15, {Scale = 1.05}) end)
    b.MouseLeave:Connect(function() tween(sc, 0.15, {Scale = 1}) end)
    return b, st
end

-- ---------- notificacoes ----------
local toastHolder = Instance.new("Frame", hub)
toastHolder.AnchorPoint = Vector2.new(0.5, 0); toastHolder.Position = UDim2.new(0.5, 0, 0, 70)
toastHolder.Size = UDim2.fromOffset(420, 300); toastHolder.BackgroundTransparency = 1
local tl0 = Instance.new("UIListLayout", toastHolder); tl0.Padding = UDim.new(0, 6)
tl0.HorizontalAlignment = Enum.HorizontalAlignment.Center; tl0.SortOrder = Enum.SortOrder.LayoutOrder
local floatHolder = Instance.new("Frame", hub)
floatHolder.Size = UDim2.fromOffset(300, 200); floatHolder.Position = UDim2.new(0.5, -150, 0.3, 0)
floatHolder.BackgroundTransparency = 1
local toastN, lastSpeedPop = 0, 0
simPopup = function(text, isSpeed)
    if isSpeed then
        if tick() - lastSpeedPop < 0.2 then return end
        lastSpeedPop = tick()
        local t = label(floatHolder, text, 28, FT, TH.a1)
        t.Size = UDim2.new(1, 0, 0, 34); t.Position = UDim2.new(0, math.random(-50, 50), 0.6, 0)
        t.TextStrokeTransparency = 0.3
        tween(t, 0.9, {Position = t.Position - UDim2.fromOffset(0, 80), TextTransparency = 1, TextStrokeTransparency = 1})
        task.delay(0.95, function() t:Destroy() end)
        return
    end
    toastN = toastN + 1
    playSnd(toastSnd)
    local p = Instance.new("Frame", toastHolder)
    p.Size = UDim2.fromOffset(0, 36); p.AutomaticSize = Enum.AutomaticSize.X; p.BackgroundColor3 = TH.bg
    p.BackgroundTransparency = 0.05; p.LayoutOrder = toastN; corner(p, 18); stroke(p, 1.5, true)
    local pad = Instance.new("UIPadding", p); pad.PaddingLeft = UDim.new(0, 18); pad.PaddingRight = UDim.new(0, 18)
    local t = label(p, text, 14, FB); t.Size = UDim2.new(0, 0, 1, 0); t.AutomaticSize = Enum.AutomaticSize.X
    local s = Instance.new("UIScale", p); s.Scale = 0.6
    tween(s, 0.3, {Scale = 1}, Enum.EasingStyle.Back)
    task.delay(2.6, function()
        tween(s, 0.25, {Scale = 0.6}); tween(p, 0.25, {BackgroundTransparency = 1}); tween(t, 0.25, {TextTransparency = 1})
        task.delay(0.3, function() p:Destroy() end)
    end)
end

-- =====================================================================
-- ABA: PETS
-- =====================================================================
local pPets = newPage("Pets", "🐾", 1)
section(pPets, "Escolha o pet")
local searchBox = Instance.new("TextBox", pPets)
searchBox.Size = UDim2.new(1, 0, 0, 38); searchBox.BackgroundColor3 = TH.card; searchBox.TextColor3 = TH.text
searchBox.PlaceholderText = "🔍  Buscar pet..."; searchBox.PlaceholderColor3 = TH.sub; searchBox.Text = ""
searchBox.ClearTextOnFocus = false; searchBox.Font = FB; searchBox.TextSize = 14
searchBox.TextXAlignment = Enum.TextXAlignment.Left; searchBox.LayoutOrder = nextOrder(pPets)
corner(searchBox, 10); stroke(searchBox, 1, true, 0.5)
local sbPad = Instance.new("UIPadding", searchBox); sbPad.PaddingLeft = UDim.new(0, 12)

local countLbl = label(pPets, "", 11, FB, TH.sub)
countLbl.Size = UDim2.new(1, 0, 0, 14); countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.LayoutOrder = nextOrder(pPets)
local list = Instance.new("ScrollingFrame", pPets)
list.Size = UDim2.new(1, 0, 0, 236); list.BackgroundColor3 = TH.panel; list.BorderSizePixel = 0
list.ScrollBarThickness = 3; list.ScrollBarImageColor3 = TH.a1; list.LayoutOrder = nextOrder(pPets)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y; list.CanvasSize = UDim2.new()
corner(list, 12)
local lpad = Instance.new("UIPadding", list)
lpad.PaddingTop = UDim.new(0, 8); lpad.PaddingLeft = UDim.new(0, 8); lpad.PaddingRight = UDim.new(0, 8); lpad.PaddingBottom = UDim.new(0, 8)
local grid = Instance.new("UIGridLayout", list)
grid.CellSize = UDim2.fromOffset(84, 102); grid.CellPadding = UDim2.fromOffset(8, 8)
if UIS.TouchEnabled and not UIS.KeyboardEnabled then grid.CellSize = UDim2.fromOffset(92, 110) end
grid.SortOrder = Enum.SortOrder.LayoutOrder

local selected
local names = petNames()
local cells = {}
local function paintSel()
    for n, c in pairs(cells) do
        local on = (n == selected)
        c.btn.BackgroundColor3 = on and TH.card2 or TH.card
        c.st.Transparency = on and 0 or 1
    end
end

-- TODOS os pets na grade; a imagem 3D so e criada quando o quadrado aparece na tela (leve)
local function loadVisible()
    if not list.Parent or not pPets.Visible then return end
    local top = list.AbsolutePosition.Y - 120
    local bottom = list.AbsolutePosition.Y + list.AbsoluteSize.Y + 120
    for _, c in pairs(cells) do
        if not c.loaded and c.src then
            local y = c.btn.AbsolutePosition.Y
            if y + c.btn.AbsoluteSize.Y >= top and y <= bottom then
                c.loaded = true
                makeThumb(c.btn, c.src)
            end
        end
    end
end
list:GetPropertyChangedSignal("CanvasPosition"):Connect(loadVisible)
task.spawn(function()
    while task.wait(0.5) do
        if not alive() then break end
        pcall(loadVisible)
    end
end)

local function rebuild(filter)
    for _, c in pairs(cells) do c.btn:Destroy() end
    cells = {}
    filter = (filter or ""):lower()
    local shown = 0
    for _, n in ipairs(names) do
        if filter == "" or n:lower():find(filter, 1, true) then
            shown = shown + 1
            local b, st = thumbCell(list, nil, n, shown)
            b.MouseButton1Click:Connect(function()
                selected = n; chosenPet = n
                setStatus("Selecionado: " .. n .. " (spawn e roubo)"); paintSel()
            end)
            cells[n] = {btn = b, st = st, src = RS.AssetModels:FindFirstChild(n), loaded = false}
        end
    end
    paintSel()
    list.CanvasPosition = Vector2.zero
    countLbl.Text = filter == "" and ("🐾 " .. shown .. " pets no jogo  •  role pra ver todos")
        or ("🔍 " .. shown .. " de " .. #names .. " pets")
    task.defer(loadVisible)
end
local searchToken = 0
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchToken = searchToken + 1
    local my = searchToken
    task.delay(0.35, function() if my == searchToken then rebuild(searchBox.Text) end end)
end)
rebuild("")

row(pPets, {
    {"✨ Spawnar pet", "main", function()
        if not selected then setStatus("Escolha um pet na grade") return end
        local src = RS.AssetModels:FindFirstChild(selected)
        if src and spawnModel(src, selected) then
            setStatus("Spawnou: " .. selected .. " (" .. #spawned .. ") — " .. mode)
            simPopup("✨ " .. selected .. " spawnado!")
        else setStatus("Falhou: " .. selected) end
    end},
    {"🥚 Copiar ovo perto", "card", function()
        local e = nearestEgg()
        if e and spawnModel(e, "Egg") then setStatus("Ovo copiado (" .. #spawned .. ")") else setStatus("Nenhum ovo perto") end
    end},
})

section(pPets, "Onde os pets ficam")
local modeBtns
local function paintModes()
    for m, b in pairs(modeBtns) do styleBtn(b, m == mode and "main" or "card") end
end
local function setMode(m)
    mode = m
    if m == "Fixo" then
        local r = root()
        if r then
            local _, yaw = r.CFrame:ToEulerAnglesYXZ()
            fixedAnchor = CFrame.new(r.Position) * CFrame.fromEulerAnglesYXZ(0, yaw, 0) * CFrame.new(0, 0, 4)
            local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            fixedFeetY = r.Position.Y - r.Size.Y / 2 - (hum and hum.HipHeight or 2)
        end
    end
    layout()
    paintModes()
    if mode == "Base" then setStatus("Na base (plot " .. tostring(mySlot or "?") .. ")")
    elseif mode == "Fixo" then setStatus("Fixado aqui")
    else setStatus("Seguindo voce") end
end
local mb = row(pPets, {
    {"🏠 Base", "card", function() setMode("Base") end},
    {"📌 Fixar aqui", "card", function() setMode("Fixo") end},
    {"🐾 Seguir", "card", function() setMode("Seguir") end},
})
modeBtns = {Base = mb[1], Fixo = mb[2], Seguir = mb[3]}
paintModes()

cycle(pPets, "📏 Tamanho dos pets", function()
    return (scale == 1 and "Original" or (scale .. "x"))
end, function()
    local opts = {0.5, 0.75, 1, 1.5, 2, 3}
    local i = table.find(opts, scale) or 3
    scale = opts[i % #opts + 1]
    layout()
    simPopup("📏 Tamanho: " .. (scale == 1 and "original" or (scale .. "x")))
end)
toggle(pPets, "🚶 Pets passeiam pelo cercado", function() return wander end, function(v) wander = v end)
row(pPets, {
    {"↩ Remover último", "card", function()
        local s = table.remove(spawned)
        if s then s.model:Destroy() end
        layout(); setStatus("Total: " .. #spawned)
    end},
    {"🗑 Limpar tudo", "bad", function()
        for _, s in ipairs(spawned) do s.model:Destroy() end
        spawned = {}; setStatus("Limpo")
    end},
})

-- =====================================================================
-- ABA: BASE
-- =====================================================================
local pBase = newPage("Base", "🏰", 2)
section(pBase, "Sua base")
button(pBase, "📍 Minha base é aqui (plot mais perto)", "main", function()
    local r = root(); if not r then return end
    local p = nearestPlot(r.Position)
    if p then mySlot = p.Name; setMode("Base"); setStatus("Base definida: plot " .. p.Name); simPopup("📍 Base: plot " .. p.Name) end
end)
section(pBase, "Base no nível máximo")
row(pBase, {
    {"🏰 Base máxima", "gold", function() applyMaxBase() end},
    {"↩ Original", "card", function() removeMaxBase() end},
})
section(pBase, "Esteira")
row(pBase, {
    {"🏃 Esteira máxima / trocar", "gold", function() nextTreadmill() end},
    {"↩ Original", "card", function() removeTreadmill() end},
})
local treadNote = note(pBase, "Suba na esteira: o +24 do tênis vira o valor escolhido abaixo.")
cycle(pBase, "👟 Ganho no tênis da esteira", function() return "+" .. fmtMoney(GK.treadBonus) end, function()
    local opts = {300000, 1000000, 10000000, 100000000, 1000000000}
    local i = table.find(opts, GK.treadBonus) or 0
    GK.treadBonus = opts[i % #opts + 1]
end)
task.spawn(function()
    while task.wait(1) do
        if not alive() then break end
        if rewriteCount > 0 then treadNote.Text = "✅ Números do jogo trocados: " .. rewriteCount end
    end
end)

-- =====================================================================
-- ABA: ROUBO
-- =====================================================================
local pSteal = newPage("Roubo", "🎯", 3)
section(pSteal, "Pet do roubo")
local petCard = Instance.new("Frame", pSteal)
petCard.Size = UDim2.new(1, 0, 0, 92); petCard.BackgroundColor3 = TH.card; petCard.LayoutOrder = nextOrder(pSteal)
corner(petCard, 12); stroke(petCard, 1.5, true, 0.2)
local petThumbHolder = Instance.new("Frame", petCard)
petThumbHolder.Position = UDim2.fromOffset(8, 8); petThumbHolder.Size = UDim2.fromOffset(76, 76)
petThumbHolder.BackgroundTransparency = 1
local petName = label(petCard, "", 18, FT); petName.Position = UDim2.fromOffset(96, 14)
petName.Size = UDim2.new(1, -200, 0, 26); petName.TextXAlignment = Enum.TextXAlignment.Left; petName.TextScaled = true
local petHint = label(petCard, "", 12, FN, TH.sub); petHint.Position = UDim2.fromOffset(96, 44)
petHint.Size = UDim2.new(1, -200, 0, 36); petHint.TextXAlignment = Enum.TextXAlignment.Left; petHint.TextWrapped = true
local clearPet = mkBtn(petCard, "✖ Limpar", "card", function() chosenPet = nil end)
clearPet.AnchorPoint = Vector2.new(1, 0.5); clearPet.Position = UDim2.new(1, -10, 0.5, 0); clearPet.Size = UDim2.fromOffset(90, 34)
local lastShownPet = -1
task.spawn(function()
    while task.wait(0.4) do
        if not alive() then break end
        if chosenPet ~= lastShownPet then
            lastShownPet = chosenPet
            for _, c in ipairs(petThumbHolder:GetChildren()) do c:Destroy() end
            if chosenPet then
                local src = RS.AssetModels:FindFirstChild(chosenPet)
                if src then local vf = makeThumb(petThumbHolder, src); vf.Size = UDim2.fromScale(1, 1); vf.Position = UDim2.new() end
                petName.Text = chosenPet
                local ar, src2 = petArea(chosenPet)
                petHint.Text = "📍 " .. tostring(ar or "área desconhecida") .. (src2 and ("  •  " .. src2) or "")
                clearPet.Visible = true
            else
                petName.Text = "Pet do próprio ovo"
                petHint.Text = "Escolha um pet na aba 🐾 Pets pra roubar ele"
                clearPet.Visible = false
            end
        end
    end
end)

section(pSteal, "Ação")
row(pSteal, {
    {"🎯 Escolher ovo", "card", function() end},   -- ligado abaixo (janela)
    {"🏃 ROUBAR", "main", function()
        if simAuto then simAuto = false end
        pcall(tripSteal)
    end},
    {"⛔ Parar", "bad", function()
        tripCancel = true; simAuto = false
        simPopup("⛔ Viagem cancelada")
    end},
}, 46)
section(pSteal, "Automático")
local refreshAuto = toggle(pSteal, "🤖 Auto roubar (repete sozinho)", function() return simAuto end, function(v) simAuto = v end)
toggle(pSteal, "👤 Auto usa o personagem", function() return charMode end, function(v) charMode = v end)
cycle(pSteal, "🌍 Área (sem pet escolhido)", function() return simArea end, function()
    local i = table.find(SIM_AREAS, simArea) or 1
    simArea = SIM_AREAS[i % #SIM_AREAS + 1]
end)
section(pSteal, "Correr Flash (só na sua tela)")
local refreshRun = toggle(pSteal, "🏃 Correr Flash (controle com WASD/analógico)", function() return GK.isRunning() end, function(v)
    if v then GK.startRun() else GK.stopRun() end
end)
cycle(pSteal, "💨 Velocidade da corrida", function() return tostring(GK.runSpeed) end, function()
    local opts = {150, 300, 600, 1200, 3000}
    local i = table.find(opts, GK.runSpeed) or 0
    GK.runSpeed = opts[i % #opts + 1]
end)
task.spawn(function()
    local last = GK.isRunning()
    while task.wait(0.3) do
        if not alive() then GK.stopRun() break end
        if GK.isRunning() ~= last then last = GK.isRunning(); refreshRun() end
    end
end)
toggle(pSteal, "⚡ Efeito Flash no meu personagem", function() return GK.flashChar end, function(v) GK.flashChar = v end)
cycle(pSteal, "⚡ Velocidade do roubo", function() return GK.speedMode end, function()
    local modes = {"Esteira", "Flash", "Super Flash", "Instantâneo"}
    local i = table.find(modes, GK.speedMode) or 1
    GK.speedMode = modes[i % #modes + 1]
end)
cycle(pSteal, "⏱ Tempo pra chocar", function() return GK.hatchMode end, function()
    GK.hatchMode = GK.hatchMode == "Rápido" and "Real" or "Rápido"
end)
toggle(pSteal, "✨ Aviso do jogo ao entregar ovo", function() return GK.gameFx end, function(v) GK.gameFx = v end)
button(pSteal, "🥚 Roubar 1 (ovo voa sozinho)", "card", function() pcall(simStealOne) end)
task.spawn(function()
    local last = simAuto
    while task.wait(0.3) do
        if not alive() then break end
        if simAuto ~= last then last = simAuto; refreshAuto() end
    end
end)

-- =====================================================================
-- ABA: STATUS
-- =====================================================================
local pStats = newPage("Status", "💰", 4)
section(pStats, "Seu progresso")
local statsGrid = Instance.new("Frame", pStats)
statsGrid.Size = UDim2.new(1, 0, 0, 2 * 66 + 10); statsGrid.BackgroundTransparency = 1; statsGrid.LayoutOrder = nextOrder(pStats)
local sgl = Instance.new("UIGridLayout", statsGrid)
sgl.CellSize = UDim2.new(0.5, -5, 0, 66); sgl.CellPadding = UDim2.fromOffset(10, 10)
local vMoney = statCard(statsGrid, "💰", "Dinheiro", TH.ok)
local vInc   = statCard(statsGrid, "📈", "Por segundo", Color3.fromRGB(170, 240, 190))
local vSpeed = statCard(statsGrid, "⚡", "Velocidade", TH.a1)
local vSteal = statCard(statsGrid, "🥚", "Roubados / Chocados", TH.gold)
button(pStats, "🔄 Zerar progresso", "bad", function()
    sim.money, sim.speed, sim.stolen, sim.hatched = 0, 16, 0, 0
    simSave(); simPopup("🔄 Progresso zerado")
end)
task.spawn(function()
    while task.wait(0.25) do
        if not alive() then hub:Destroy() break end
        vMoney.Text = "$" .. fmtMoney(sim.money)
        vInc.Text = "+$" .. fmtMoney(sim.income or 0) .. "/s"
        vSpeed.Text = fmtMoney(sim.speed)
        vSteal.Text = sim.stolen .. "  /  " .. sim.hatched
        hStats.Text = "💰 $" .. fmtMoney(sim.money) .. "    ⚡ " .. fmtMoney(sim.speed)
        dot.BackgroundColor3 = isTripBusy() and TH.gold or TH.ok
    end
end)

-- =====================================================================
-- ABA: EXTRA
-- =====================================================================
-- =====================================================================
-- ABA: SKINS (so voce ve)
-- =====================================================================
do
    local pSkin = newPage("Skins", "👕", 5)
    local function done(ok, msg, okText)
        simPopup(ok and ("✅ " .. (okText or "Pronto")) or ("❌ " .. tostring(msg)))
    end
    local function inputRow(pg, placeholder, btnText, cb)
        local fr = Instance.new("Frame", pg)
        fr.Size = UDim2.new(1, 0, 0, 44); fr.BackgroundTransparency = 1; fr.LayoutOrder = nextOrder(pg)
        local tb = Instance.new("TextBox", fr)
        tb.Size = UDim2.new(1, -140, 1, 0); tb.BackgroundColor3 = TH.card; tb.TextColor3 = TH.text
        tb.PlaceholderText = placeholder; tb.PlaceholderColor3 = TH.sub; tb.Text = ""
        tb.Font = FN; tb.TextSize = 14; tb.ClearTextOnFocus = false
        corner(tb, 10)
        local b = mkBtn(fr, btnText, "main", function() cb(tb.Text) end)
        b.AnchorPoint = Vector2.new(1, 0); b.Position = UDim2.new(1, 0, 0, 0); b.Size = UDim2.new(0, 130, 1, 0)
        return tb
    end

    section(pSkin, "✨ Rastros do jogo")
    local trails = GK.trailNames()
    if #trails == 0 then note(pSkin, "Não achei os rastros do jogo (Assets.Trails).") end
    for i = 1, #trails, 3 do
        local items = {}
        for j = i, math.min(i + 2, #trails) do
            local n = trails[j]
            table.insert(items, {n:gsub("Trail$", ""), (j >= #trails - 3) and "main" or "card", function()
                local ok = GK.wearTrail(n)
                done(ok, "não deu pra colocar " .. n, "Rastro: " .. n)
            end})
        end
        row(pSkin, items, 40)
    end
    button(pSkin, "❌ Tirar rastro", "card", function() GK.wearTrail(nil); simPopup("Rastro removido") end)

    section(pSkin, "💎 Itens raros")
    for i = 1, #GK.PRESETS, 2 do
        local items = {}
        for j = i, math.min(i + 1, #GK.PRESETS) do
            table.insert(items, {GK.PRESETS[j][1], "card", function()
                simPopup("⏳ Vestindo " .. GK.PRESETS[j][1] .. "...")
                local ok, msg = GK.wearPreset(j)
                done(ok, msg, GK.PRESETS[j][1])
            end})
        end
        row(pSkin, items, 42)
    end
    note(pSkin, "Os itens se somam: dá pra usar Headless + Dominus + Valkyrie juntos.")
    inputRow(pSkin, "ID de qualquer item do catálogo", "👕 Vestir", function(t)
        simPopup("⏳ Procurando item...")
        local ok, msg = GK.wearItem(t)
        done(ok, msg, msg)
    end)

    section(pSkin, "👤 Copiar avatar")
    inputRow(pSkin, "Nome ou ID de qualquer jogador", "📋 Copiar", function(t)
        simPopup("⏳ Copiando avatar...")
        local ok, msg = GK.wearUser(t)
        done(ok, msg, "Avatar de " .. t)
    end)
    local plist = Instance.new("Frame", pSkin)
    plist.Size = UDim2.new(1, 0, 0, 0); plist.AutomaticSize = Enum.AutomaticSize.Y
    plist.BackgroundTransparency = 1; plist.LayoutOrder = nextOrder(pSkin)
    local gl = Instance.new("UIGridLayout", plist)
    gl.CellSize = UDim2.new(0.5, -5, 0, 38); gl.CellPadding = UDim2.fromOffset(10, 8)
    local function fillPlayers()
        for _, c in ipairs(plist:GetChildren()) do if c:IsA("GuiButton") then c:Destroy() end end
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl ~= LP then
                mkBtn(plist, "👤 " .. pl.DisplayName, "card", function()
                    if not pl.Character then simPopup("❌ " .. pl.DisplayName .. " sem personagem agora") return end
                    GK.curDesc = nil
                    local ok, msg = GK.wearModel(pl.Character)
                    done(ok, msg, "Avatar de " .. pl.DisplayName)
                end)
            end
        end
    end
    button(pSkin, "🔄 Jogadores do servidor (toque pra copiar)", "card", fillPlayers)
    fillPlayers()
    button(pSkin, "↩️ Voltar ao meu avatar", "bad", function() GK.resetLook(); simPopup("Avatar normal de volta") end)
    note(pSkin, "Tudo aqui aparece só pra você. Pros outros jogadores nada muda.")
end

local pExtra = newPage("Extra", "⚙️", 6)
section(pExtra, "Tamanho do menu")
cycle(pExtra, "📱 Tamanho do menu", function()
    return (sim.uiMul and sim.uiMul > 0) and (math.floor(sim.uiMul * 100 + 0.5) .. "%") or "Automático"
end, function()
    local opts = {0, 0.55, 0.65, 0.75, 0.85, 1}
    local cur = sim.uiMul or 0
    local i = 1
    for k, v in ipairs(opts) do if math.abs(v - cur) < 0.01 then i = k end end
    sim.uiMul = opts[i % #opts + 1]
    simSave()
    if GK.applyUI then GK.applyUI() end
end)
section(pExtra, "Diagnóstico")
local function copyDiagnostic()
    local o = {}
    local function L(t) table.insert(o, t) end
    L("versao: " .. VERSION .. " | sessao ok: " .. tostring(alive()))
    L("pets aprendidos das bases: " .. GK.count() .. " | placa do jogo: " .. tostring(GK.template ~= nil) .. " | chocar: " .. GK.hatchMode)
    L("modo: " .. mode .. " | mySlot: " .. tostring(mySlot) .. " | plot achado: " .. tostring(myPlot() and myPlot().Name))
    local a = baseAnchor()
    L("ancora base: " .. (a and tostring(a.Position) or "nil"))
    local r = root()
    L("minha pos: " .. (r and tostring(r.Position) or "nil"))
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, p in ipairs(plots:GetChildren()) do
            local c, s = p:FindFirstChild("CenterPoint"), p:FindFirstChild("SpawnPoint")
            L(("plot %s centro=%s spawn=%s"):format(p.Name, c and tostring(c.Position) or "-", s and tostring(s.Position) or "-"))
        end
    end
    L("pets spawnados: " .. #spawned)
    for i, s in ipairs(spawned) do
        L(("  %d %s home=%s pos=%s anim=%s"):format(i, s.model.Name, s.home and tostring(s.home.Position) or "nil",
            tostring(s.model:GetPivot().Position), tostring(s.animated)))
    end
    -- raio-x da animacao de cada pet seu
    local function rigInfo(model)
        local mot, bones, anch, free = 0, 0, 0, 0
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("Motor6D") then mot = mot + 1
            elseif d:IsA("Bone") then bones = bones + 1
            elseif d:IsA("BasePart") then if d.Anchored then anch = anch + 1 else free = free + 1 end end
        end
        return ("motor6d=%d ossos=%d pecas presas=%d soltas=%d"):format(mot, bones, anch, free)
    end
    for i, s in ipairs(spawned) do
        if i > 8 then break end
        local nm = s.petName or "?"
        local e = GK.info[nm] or {}
        L(("RAIOX %s | criadas=%s | %s | memoria idle=%s walk=%s | rig nosso=%s jogo=%s | daRender=%s"):format(nm,
            tostring(s.model:GetAttribute("MV_Rigged")), rigInfo(s.model),
            tostring(e.anims and e.anims.idle), tostring(e.anims and e.anims.walk),
            GK.rigSig(s.model), tostring(e.rig), tostring(s.fromRender)))
        for _, an in ipairs(s.model:GetDescendants()) do
            if an:IsA("Animator") then
                local list = an:GetPlayingAnimationTracks()
                L(("   animator em %s: %d tocando"):format(an.Parent and an.Parent.Name or "?", #list))
                for _, tr in ipairs(list) do
                    L(("     %s len=%.2f pos=%.2f vel=%.2f peso=%.2f tocando=%s"):format(
                        tr.Animation and tr.Animation.AnimationId or "?", tr.Length, tr.TimePosition, tr.Speed, tr.WeightCurrent, tostring(tr.IsPlaying)))
                end
            end
        end
        -- o mesmo pet de verdade numa base, pra comparar
        local cra1 = workspace:FindFirstChild("ClientRenderedAssets")
        if cra1 then
            for _, pm in ipairs(cra1:GetChildren()) do
                local data = pm:FindFirstChild("Data")
                local dn = data and data:FindFirstChild("DisplayName")
                if GK.baseName(pm, dn and dn.Text or nil) == nm then
                    L("   REAL: " .. rigInfo(pm))
                    local joints = {}
                    for _, j in ipairs(pm:GetDescendants()) do
                        if j:IsA("Motor6D") then table.insert(joints, (j.Part0 and j.Part0.Name or "?") .. ">" .. (j.Part1 and j.Part1.Name or "?")) end
                    end
                    L("   REAL juntas: " .. table.concat(joints, ", "):sub(1, 600))
                    break
                end
            end
        end
        local mj = {}
        for _, j in ipairs(s.model:GetDescendants()) do
            if j:IsA("Motor6D") then table.insert(mj, (j.Part0 and j.Part0.Name or "?") .. ">" .. (j.Part1 and j.Part1.Name or "?")) end
        end
        L("   NOSSO juntas: " .. table.concat(mj, ", "):sub(1, 600))
    end
    for _, d in ipairs(animDebug) do
        L(("anim %s ctrl=%s live=%s config=%s index=%s total=%s tocou=%s err=%s"):format(d.pet, d.controller,
            tostring(d.live), tostring(d.config), tostring(d.index), tostring(d.total), tostring(d.played), tostring(d.err)))
    end
    -- chaves da config do 1o pet (pra achar onde fica a animacao)
    if spawned[1] then
        local nm = spawned[1].model.Name:gsub("^Visual_", "")
        local ok, cfg = pcall(function() return require(RS.Data.Assets.Configs[nm]) end)
        if ok and type(cfg) == "table" then
            local ks = {}
            for k, v in pairs(cfg) do table.insert(ks, tostring(k) .. "=" .. (type(v) == "table" and "{tab}" or tostring(v):sub(1, 40))) end
            L("config " .. nm .. ": " .. table.concat(ks, ", "):sub(1, 900))
        else
            L("config " .. nm .. ": require falhou -> " .. tostring(cfg))
        end
    end
    L("Animation objects no jogo: " .. (animIndex and #animIndex or "nao indexado"))
    -- onde o id da animacao real aparece no jogo
    local cra0 = workspace:FindFirstChild("ClientRenderedAssets")
    local sample
    if cra0 then
        for _, pm in ipairs(cra0:GetChildren()) do
            local t = {}; tracksOf(pm, t)
            if t[1] then sample = t[1].id:match("%d+") break end
        end
    end
    if sample then
        local hits = 0
        for _, d in ipairs(RS:GetDescendants()) do
            local hit = (d:IsA("Animation") and d.AnimationId:find(sample, 1, true))
                or (d:IsA("StringValue") and d.Value:find(sample, 1, true))
            if not hit then
                for k, v in pairs(d:GetAttributes()) do
                    if tostring(v):find(sample, 1, true) then hit = true break end
                end
            end
            if hit then hits = hits + 1; L("id " .. sample .. " achado em: " .. d:GetFullName()) if hits >= 5 then break end end
        end
        if hits == 0 then L("id " .. sample .. " nao achado em ReplicatedStorage") end
    end
    -- como o jogo anima os pets reais
    local cra = workspace:FindFirstChild("ClientRenderedAssets")
    local n = 0
    if cra then
        for _, pm in ipairs(cra:GetChildren()) do
            n = n + 1
            if n > 6 then break end
            local tracks = {}
            for _, an in ipairs(pm:GetDescendants()) do
                if an:IsA("Animator") then
                    for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
                        table.insert(tracks, tr.Name .. "=" .. (tr.Animation and tr.Animation.AnimationId or "?"))
                    end
                end
            end
            local kids = {}
            for _, c in ipairs(pm:GetChildren()) do table.insert(kids, c.ClassName .. ":" .. c.Name) end
            L(("real %s tags=[%s] tracks=[%s] filhos=[%s]"):format(pm.Name,
                table.concat(realPetTags(pm), ","), table.concat(tracks, ", "), table.concat(kids, ", "):sub(1, 200)))
        end
    end
    local txt = table.concat(o, "\n")
    pcall(function() setclipboard(txt) end)
    pcall(function() writefile("modvip_visual_debug.txt", txt) end)
    setStatus("Diagnostico copiado! Cole no chat")
end
button(pExtra, "🐞 Copiar diagnóstico", "card", copyDiagnostic)
button(pExtra, "📋 Info do pet escolhido", "card", function()
    if not chosenPet then simPopup("Escolha um pet na aba 🐾 Pets") return end
    local txt = petInfoText(chosenPet)
    pcall(function() setclipboard(txt) end)
    pcall(function() writefile("modvip_pet_info.txt", txt) end)
    simPopup("📋 Info copiada! Cole no chat")
end)
section(pExtra, "Atalhos")
note(pExtra, (UIS.TouchEnabled and not UIS.KeyboardEnabled) and "Toque no botão redondo 99NS22 pra abrir/fechar. Arraste ele pra qualquer lugar." or "RightShift abre/fecha o menu. Arraste o botão redondo 99NS22 pra qualquer lugar.")

-- =====================================================================
-- JANELA: ESCOLHER OVO
-- =====================================================================
local pickBox = Instance.new("Frame", hub)
pickBox.AnchorPoint = Vector2.new(0.5, 0.5); pickBox.Position = UDim2.fromScale(0.5, 0.5)
pickBox.Size = UDim2.fromOffset(520, 420); pickBox.BackgroundTransparency = 1
pickResp = Instance.new("UIScale", pickBox)
local pick = Instance.new("Frame", pickBox)
pick.AnchorPoint = Vector2.new(0.5, 0.5); pick.Position = UDim2.fromScale(0.5, 0.5)
pick.Size = UDim2.fromScale(1, 1); pick.BackgroundColor3 = TH.bg; pick.Visible = false; pick.Active = true
pick.ZIndex = 20
corner(pick, 18); stroke(pick, 2, true)
local pickScale = Instance.new("UIScale", pick)
local pHead = Instance.new("Frame", pick); pHead.Size = UDim2.new(1, 0, 0, 52); pHead.BackgroundTransparency = 1
local pTitle = label(pHead, "🎯 ESCOLHA O OVO", 18, FT); pTitle.Position = UDim2.fromOffset(18, 0)
pTitle.Size = UDim2.new(1, -140, 1, 0); pTitle.TextXAlignment = Enum.TextXAlignment.Left
makeDraggable(pHead, pickBox)
local pClose = mkBtn(pHead, "✕", "bad", function() pick.Visible = false end)
pClose.AnchorPoint = Vector2.new(1, 0.5); pClose.Position = UDim2.new(1, -14, 0.5, 0); pClose.Size = UDim2.fromOffset(34, 34)
local pList = Instance.new("ScrollingFrame", pick)
pList.Position = UDim2.fromOffset(14, 56); pList.Size = UDim2.new(1, -28, 1, -70)
pList.BackgroundColor3 = TH.panel; pList.BorderSizePixel = 0; pList.ScrollBarThickness = 3
pList.ScrollBarImageColor3 = TH.a2; pList.AutomaticCanvasSize = Enum.AutomaticSize.Y; pList.CanvasSize = UDim2.new()
corner(pList, 12)
local plpad = Instance.new("UIPadding", pList)
plpad.PaddingTop = UDim.new(0, 8); plpad.PaddingLeft = UDim.new(0, 8); plpad.PaddingRight = UDim.new(0, 8); plpad.PaddingBottom = UDim.new(0, 8)
local pgl = Instance.new("UIGridLayout", pList)
pgl.CellSize = UDim2.fromOffset(110, 128); pgl.CellPadding = UDim2.fromOffset(8, 8)
pgl.SortOrder = Enum.SortOrder.LayoutOrder
local pRefresh

local AREA_ORDER = {}
for i, a in ipairs(SIM_AREAS) do AREA_ORDER[a] = i end

local function selectEgg(m)
    selectedEgg = m
    if selectHL then selectHL:Destroy() end
    selectHL = Instance.new("Highlight")
    selectHL.FillColor = TH.gold; selectHL.OutlineColor = Color3.new(1, 1, 1)
    selectHL.FillTransparency = 0.4; selectHL.Adornee = m; selectHL.Parent = folder
    local info = eggCat[m.Name]
    simPopup("🎯 Ovo escolhido: " .. ((info and info.cat) or "Ovo"))
end

local function fillPicker()
    for _, c in ipairs(pList:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
    local f = workspace:FindFirstChild("AreaEggSlotsClient")
    if not f then return end
    local eggs = {}
    for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") then
            local info = eggCat[m.Name]
            local area = (info and info.area) or m.Name:match("_([%a ]+):Slot_") or "?"
            table.insert(eggs, {m = m, cat = info and info.cat, area = area})
        end
    end
    table.sort(eggs, function(a, b) return (AREA_ORDER[a.area] or 0) > (AREA_ORDER[b.area] or 0) end)
    pTitle.Text = "🎯 ESCOLHA O OVO  •  " .. #eggs .. " no mapa"
    for i, e in ipairs(eggs) do
        if i > 60 then break end
        local b = thumbCell(pList, e.m, (e.cat or "Ovo") .. " • " .. e.area, i)
        b.MouseButton1Click:Connect(function()
            if e.m.Parent then selectEgg(e.m) end
            pick.Visible = false
        end)
    end
end
pRefresh = mkBtn(pHead, "🔄", "card", fillPicker)
pRefresh.AnchorPoint = Vector2.new(1, 0.5); pRefresh.Position = UDim2.new(1, -56, 0.5, 0); pRefresh.Size = UDim2.fromOffset(40, 34)

-- liga o botao "Escolher ovo" da aba Roubo
for _, fr in ipairs(pSteal:GetChildren()) do
    if fr:IsA("Frame") then
        for _, b in ipairs(fr:GetChildren()) do
            if b:IsA("TextButton") and b.Text == "🎯 Escolher ovo" then
                b.MouseButton1Click:Connect(function()
                    fillPicker(); pick.Visible = true
                    pickScale.Scale = 0.85; tween(pickScale, 0.3, {Scale = 1}, Enum.EasingStyle.Back)
                end)
            end
        end
    end
end

-- ---------- adapta a tela (PC / celular / tablet) ----------
local cam = workspace.CurrentCamera
local isTouch = UIS.TouchEnabled and not UIS.KeyboardEnabled
local function applyResponsive()
    local vp = cam.ViewportSize
    -- tamanho do menu: automatico (menor no celular) ou o escolhido na aba Extra
    local mul = (sim.uiMul and sim.uiMul > 0) and sim.uiMul or (isTouch and 0.72 or 1)
    local sc = math.clamp(math.min((vp.X - 20) / WW, (vp.Y - 20) / WH), 0.4, 1) * mul
    respScale.Scale = sc
    local compact = isTouch or vp.X < 900 or sc < 0.85
    -- barra lateral: so icones no modo compacto
    side.Size = compact and UDim2.new(0, 58, 1, -110) or UDim2.new(0, 150, 1, -110)
    pagesHolder.Position = compact and UDim2.fromOffset(84, 62) or UDim2.fromOffset(176, 62)
    pagesHolder.Size = compact and UDim2.new(1, -98, 1, -110) or UDim2.new(1, -190, 1, -110)
    for _, t in pairs(tabs) do
        t.tx.Visible = not compact
        local ic = t.btn:FindFirstChildWhichIsA("TextLabel")
        if ic then
            ic.Size = compact and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 26, 1, 0)
            ic.Position = compact and UDim2.new() or UDim2.fromOffset(10, 0)
        end
    end
    chip.Visible = vp.X >= 520
    -- botao redondo menor no celular
    local o = isTouch and 52 or 78
    orb.Size = UDim2.fromOffset(o, o)
    orbHolder.Size = UDim2.fromOffset(o + 8, o + 8)
    -- notificacoes cabem na tela
    toastHolder.Size = UDim2.fromOffset(math.min(420, vp.X - 20), 300)
    toastHolder.Position = UDim2.new(0.5, 0, 0, isTouch and 50 or 70)
    -- janela de escolher ovo
    pickResp.Scale = math.clamp(math.min((vp.X - 20) / 520, (vp.Y - 20) / 420), 0.45, 1)
end
GK.applyUI = applyResponsive
cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() if alive() then applyResponsive() end end)
applyResponsive()

-- abre na aba Pets
selectTab("Pets")
setStatus(#names .. " pets carregados  •  modo Base")
task.delay(3, function()
    if myPlot() then setStatus("Sua base: plot " .. tostring(mySlot)) else setStatus("Base não encontrada — use 📍 na aba Base") end
end)
task.delay(0.6, function() setWin(true) end)
simPopup("🎮 99NS22 HUB " .. VERSION .. " carregado")
end

-- aquecimento: faz as buscas pesadas aos poucos logo apos carregar (o clique em ROUBAR fica instantaneo)
task.spawn(function()
    task.wait(2)
    pcall(function()
        local f = RS.Assets.Models.Eggs
        for i, m in ipairs(f:GetChildren()) do
            gpos(m.Name)
            if i % 25 == 0 then task.wait() end
        end
    end)
end)

local okHub, errHub = pcall(buildHub)
if not okHub then
    warn("[99NS22 HUB] erro ao montar o menu: " .. tostring(errHub))
    pcall(function() setclipboard("[99NS22 HUB] erro: " .. tostring(errHub)) end)
end
