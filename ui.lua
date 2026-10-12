--[[
    ╔══════════════════════════════════════════════════════════════╗
    ║  AzureUI — fully custom UI (Roblox / Luau)                   ║
    ╠══════════════════════════════════════════════════════════════╣
    ║  • Draggable (PC and mobile) by the top bar                  ║
    ║  • LeftControl (PC) minimizes / restores the window          ║
    ║  • The "–" button also minimizes                             ║
    ║  • On minimize, a round logo button appears (draggable).     ║
    ║    Tap it = window comes back                                ║
    ║  • Tabs, sections, toggle, button, slider, dropdown,         ║
    ║    textbox, keybind, label and notifications                 ║
    ╚══════════════════════════════════════════════════════════════╝

    Usage example is at the end of the file (you can delete it).
]]

local env = (getgenv and getgenv()) or _G

-- If the script runs again, remove the old UI
if env.AzureUI_Cleanup then
    pcall(env.AzureUI_Cleanup)
end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

----------------------------------------------------------------------
-- GENERAL CONFIG
----------------------------------------------------------------------
local DEFAULT_ICON = 127041730095194 -- logo (replace with your asset id)

local Theme = {
    Background = Color3.fromRGB(8, 12, 19),
    Main       = Color3.fromRGB(15, 23, 34),
    Section    = Color3.fromRGB(12, 18, 28),
    Element    = Color3.fromRGB(22, 32, 47),
    Hover      = Color3.fromRGB(30, 43, 62),
    Outline    = Color3.fromRGB(31, 44, 63),
    Accent     = Color3.fromRGB(30, 144, 255),
    Text       = Color3.fromRGB(245, 245, 245),
    SubText    = Color3.fromRGB(150, 160, 175),
}

local Library = {
    Theme = Theme,
    Windows = {},
    Listening = false, -- true while a Keybind is waiting for a key
}

----------------------------------------------------------------------
-- UTILITIES
----------------------------------------------------------------------
local connections = {}

local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end

local function fire(cb, ...)
    if type(cb) ~= "function" then return end
    local args = table.pack(...)
    task.spawn(function()
        local ok, err = pcall(cb, table.unpack(args, 1, args.n))
        if not ok then warn("[AzureUI] callback error: " .. tostring(err)) end
    end)
end

local function new(class, props, children)
    local inst = Instance.new(class)
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v else inst[k] = v end
    end
    for _, child in ipairs(children or {}) do child.Parent = inst end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(inst, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end

local function stroke(inst, color, thickness)
    return new("UIStroke", {
        Color = color or Theme.Outline,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = inst,
    })
end

local function padding(inst, l, t, r, b)
    return new("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
        Parent = inst,
    })
end

local function tween(inst, time, props, style, dir)
    local t = TweenService:Create(
        inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    )
    t:Play()
    return t
end

local function label(props)
    local d = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props) do d[k] = v end
    return new("TextLabel", d)
end

local function hover(inst, normal, over)
    connect(inst.MouseEnter, function() tween(inst, 0.12, { BackgroundColor3 = over }) end)
    connect(inst.MouseLeave, function() tween(inst, 0.12, { BackgroundColor3 = normal }) end)
end

local function toAsset(icon)
    if type(icon) == "number" then return "rbxassetid://" .. icon end
    if type(icon) == "string" then
        if icon:match("^%d+$") then return "rbxassetid://" .. icon end
        return icon
    end
    return ""
end

local function screenSize()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local rng = Random.new()

local function randomSegment(len)
    local out = table.create(len)
    for i = 1, len do
        local n = rng:NextInteger(1, #CHARSET)
        out[i] = string.sub(CHARSET, n, n)
    end
    return table.concat(out)
end

-- "XXXXX-XXXXXX-XXXXX" (letras maiúsculas, minúsculas e números)
local function randomGuiName()
    return randomSegment(5) .. "-" .. randomSegment(6) .. "-" .. randomSegment(5)
end

local function getGuiParent()
    return game:GetService("CoreGui")
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

----------------------------------------------------------------------
-- DRAGGING (mouse + touch)
-- handle  = element that receives the click/touch
-- target  = element that moves (AnchorPoint 0.5, offset position)
-- clampFn = (x, y) -> x, y   keeps it on screen
-- onClick = called if released without dragging (simple tap)
----------------------------------------------------------------------
local function makeDraggable(handle, target, clampFn, onClick)
    local dragging, moved = false, false
    local startInput, dragStart, startPos

    connect(handle.InputBegan, function(input)
        if not isPress(input) then return end
        dragging, moved = true, false
        startInput = input
        dragStart = input.Position
        startPos = Vector2.new(target.Position.X.Offset, target.Position.Y.Offset)

        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                c:Disconnect()
                if dragging then
                    dragging = false
                    if not moved and onClick then onClick() end
                end
            end
        end)
    end)

    connect(UIS.InputChanged, function(input)
        if not dragging then return end
        local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
        local isTouch = input.UserInputType == Enum.UserInputType.Touch and input == startInput
        if not (isMouse or isTouch) then return end

        local d = input.Position - dragStart
        if not moved and math.sqrt(d.X * d.X + d.Y * d.Y) > 6 then moved = true end
        if not moved then return end

        local x, y = startPos.X + d.X, startPos.Y + d.Y
        if clampFn then x, y = clampFn(x, y) end
        target.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)
end

----------------------------------------------------------------------
-- ELEMENTS (toggle, button, slider...)
----------------------------------------------------------------------
local Elements = {}

local function nextOrder(ctx)
    ctx.order = ctx.order + 1
    return ctx.order
end

function Elements.Label(ctx, opts)
    if type(opts) == "string" then opts = { Text = opts } end
    opts = opts or {}
    local lbl = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = opts.Text or "Label",
        TextWrapped = true,
        TextColor3 = Theme.SubText,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    padding(lbl, 4, 2, 4, 2)
    local obj = {}
    function obj:SetText(t) lbl.Text = t end
    return obj
end

function Elements.Button(ctx, opts)
    if type(opts) == "string" then opts = { Name = opts } end
    opts = opts or {}
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = opts.Name or "Button",
        Font = Enum.Font.GothamMedium,
        TextSize = 13,
        TextColor3 = Theme.Text,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(btn, 6)
    hover(btn, Theme.Element, Theme.Hover)

    connect(btn.MouseButton1Click, function()
        btn.BackgroundColor3 = Theme.Accent
        task.delay(0.08, function()
            if btn.Parent then tween(btn, 0.25, { BackgroundColor3 = Theme.Element }) end
        end)
        fire(opts.Callback)
    end)

    local obj = {}
    function obj:SetText(t) btn.Text = t end
    return obj
end

function Elements.Toggle(ctx, opts)
    opts = opts or {}
    local value = opts.Default and true or false

    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = "",
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)
    hover(row, Theme.Element, Theme.Hover)

    label({
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -62, 1, 0),
        Text = opts.Name or "Toggle",
        Parent = row,
    })

    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(36, 18),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(track, 9)
    local knob = new("Frame", {
        Position = UDim2.new(0, 3, 0.5, -6),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 6)

    local obj = { Value = value }

    local function render(animate)
        local t = animate and 0.15 or 0
        tween(track, t, { BackgroundColor3 = obj.Value and Theme.Accent or Theme.Outline })
        tween(knob, t, { Position = obj.Value and UDim2.new(0, 21, 0.5, -6) or UDim2.new(0, 3, 0.5, -6) })
    end

    function obj:Set(v, silent)
        v = v and true or false
        if v == self.Value then return end
        self.Value = v
        render(true)
        if not silent then fire(opts.Callback, v) end
    end
    function obj:Get() return self.Value end

    connect(row.MouseButton1Click, function() obj:Set(not obj.Value) end)
    render(false)
    return obj
end

function Elements.Slider(ctx, opts)
    opts = opts or {}
    local min, max = opts.Min or 0, opts.Max or 100
    local inc = opts.Increment or 1
    local suffix = opts.Suffix or ""
    local obj = { Value = math.clamp(opts.Default or min, min, max) }

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)

    label({
        Position = UDim2.new(0, 10, 0, 6),
        Size = UDim2.new(1, -100, 0, 16),
        Text = opts.Name or "Slider",
        Parent = row,
    })
    local valLbl = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 6),
        Size = UDim2.fromOffset(90, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = Theme.SubText,
        Parent = row,
    })

    local bar = new("Frame", {
        Position = UDim2.new(0, 10, 1, -14),
        Size = UDim2.new(1, -20, 0, 6),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(bar, 3)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(fill, 3)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = fill,
    })
    corner(knob, 6)

    -- larger touch area (helps on mobile)
    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 0, 22),
        Size = UDim2.new(1, 0, 1, -22),
        BackgroundTransparency = 1,
        Text = "",
        Parent = row,
    })

    local function setValue(v, silent)
        v = math.clamp(v, min, max)
        v = math.floor((v - min) / inc + 0.5) * inc + min
        v = tonumber(string.format("%.4f", v))
        v = math.clamp(v, min, max)

        local alpha = (max > min) and (v - min) / (max - min) or 0
        fill.Size = UDim2.fromScale(alpha, 1)
        valLbl.Text = tostring(v) .. suffix

        if v ~= obj.Value then
            obj.Value = v
            if not silent then fire(opts.Callback, v) end
        end
    end

    function obj:Set(v, silent) setValue(v, silent) end
    function obj:Get() return self.Value end

    local dragging = false
    local function fromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        setValue(min + (max - min) * alpha)
    end

    connect(hit.InputBegan, function(input)
        if not isPress(input) then return end
        dragging = true
        if ctx.scroller then ctx.scroller.ScrollingEnabled = false end
        fromX(input.Position.X)

        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                c:Disconnect()
                dragging = false
                if ctx.scroller then ctx.scroller.ScrollingEnabled = true end
            end
        end)
    end)
    connect(UIS.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            fromX(input.Position.X)
        end
    end)

    -- initial value
    local initial = obj.Value
    obj.Value = nil
    setValue(initial, true)
    obj.Value = initial
    return obj
end

function Elements.Dropdown(ctx, opts)
    opts = opts or {}
    local options = opts.Options or {}
    local name = opts.Name or "Dropdown"
    local obj = { Value = opts.Default, Options = options }
    local open = false

    local wrap = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wrap })

    local head = new("TextButton", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = "",
        Parent = wrap,
    })
    corner(head, 6)
    hover(head, Theme.Element, Theme.Hover)

    local headLbl = label({
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -40, 1, 0),
        Text = "",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = head,
    })
    local arrow = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(20, 20),
        Text = ">",
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = head,
    })

    local list = new("Frame", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Visible = false,
        Parent = wrap,
    })
    corner(list, 6)
    stroke(list, Theme.Outline, 1)
    padding(list, 4, 4, 4, 4)
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

    local buttons = {}

    local function updateHead()
        headLbl.Text = name .. ": " .. (obj.Value ~= nil and tostring(obj.Value) or "-")
        for opt, b in pairs(buttons) do
            b.TextColor3 = (opt == obj.Value) and Theme.Accent or Theme.Text
        end
    end

    local function setOpen(state)
        open = state
        list.Visible = state
        tween(arrow, 0.15, { Rotation = state and 90 or 0 })
    end

    local function select(v, silent)
        obj.Value = v
        updateHead()
        if not silent then fire(opts.Callback, v) end
    end

    local function build()
        for _, b in pairs(buttons) do b:Destroy() end
        buttons = {}
        for i, opt in ipairs(obj.Options) do
            local b = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundColor3 = Theme.Background,
                AutoButtonColor = false,
                Text = tostring(opt),
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                Parent = list,
            })
            corner(b, 5)
            hover(b, Theme.Background, Theme.Element)
            connect(b.MouseButton1Click, function()
                select(opt)
                setOpen(false)
            end)
            buttons[opt] = b
        end
        updateHead()
    end

    function obj:Set(v, silent) select(v, silent) end
    function obj:Get() return self.Value end
    function obj:Refresh(newOptions, keepValue)
        self.Options = newOptions or {}
        if not keepValue then self.Value = nil end
        build()
    end

    connect(head.MouseButton1Click, function() setOpen(not open) end)
    build()
    return obj
end

function Elements.Textbox(ctx, opts)
    opts = opts or {}
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)

    label({
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -150, 1, 0),
        Text = opts.Name or "Textbox",
        Parent = row,
    })

    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(130, 24),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "...",
        PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextColor3 = Theme.Text,
        Parent = row,
    })
    corner(box, 5)
    padding(box, 6, 0, 6, 0)

    connect(box.FocusLost, function(enter) fire(opts.Callback, box.Text, enter) end)

    local obj = {}
    function obj:Set(t) box.Text = tostring(t) end
    function obj:Get() return box.Text end
    return obj
end

function Elements.Keybind(ctx, opts)
    opts = opts or {}
    local obj = { Value = opts.Default }
    local listening = false

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)

    label({
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -110, 1, 0),
        Text = opts.Name or "Keybind",
        Parent = row,
    })

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(90, 24),
        BackgroundColor3 = Theme.Background,
        AutoButtonColor = false,
        Text = "",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Theme.Text,
        Parent = row,
    })
    corner(btn, 5)

    local function render()
        btn.Text = obj.Value and obj.Value.Name or "None"
        btn.TextColor3 = Theme.Text
    end

    function obj:Set(key) self.Value = key; render() end
    function obj:Get() return self.Value end

    connect(btn.MouseButton1Click, function()
        if listening then return end
        listening = true
        Library.Listening = true
        btn.Text = "..."
        btn.TextColor3 = Theme.Accent
    end)

    connect(UIS.InputBegan, function(input)
        if listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                listening = false
                task.defer(function() Library.Listening = false end)
                if input.KeyCode == Enum.KeyCode.Escape then
                    obj.Value = nil
                else
                    obj.Value = input.KeyCode
                end
                render()
                fire(opts.Changed, obj.Value)
            end
            return
        end
        if obj.Value and input.KeyCode == obj.Value and not UIS:GetFocusedTextBox() then
            fire(opts.Callback, obj.Value)
        end
    end)

    render()
    return obj
end

local function attach(obj, ctx)
    function obj:AddLabel(o) return Elements.Label(ctx, o) end
    function obj:AddButton(o) return Elements.Button(ctx, o) end
    function obj:AddToggle(o) return Elements.Toggle(ctx, o) end
    function obj:AddSlider(o) return Elements.Slider(ctx, o) end
    function obj:AddDropdown(o) return Elements.Dropdown(ctx, o) end
    function obj:AddTextbox(o) return Elements.Textbox(ctx, o) end
    function obj:AddKeybind(o) return Elements.Keybind(ctx, o) end
end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
function Library:CreateWindow(opts)
    opts = opts or {}
    local title = opts.Title or "Azure UI"
    local subtitle = opts.Subtitle or ""
    local iconId = toAsset(opts.Icon or DEFAULT_ICON)

    local Window = {
        Tabs = {},
        Minimized = false,
        ToggleKey = opts.ToggleKey or Enum.KeyCode.LeftControl,
        FloatEnabled = opts.FloatButton,
        _destroyed = false,
    }
    if Window.FloatEnabled == nil then
        Window.FloatEnabled = true
    end

    -- ScreenGui (CoreGui, nome aleatório a cada 5s) ---------------
    local gui = new("ScreenGui", {
        Name = randomGuiName(),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
    })
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    gui.Parent = getGuiParent()
    Window.Gui = gui

    task.spawn(function()
        while not Window._destroyed and gui.Parent do
            task.wait(5)
            if Window._destroyed or not gui.Parent then break end
            gui.Name = randomGuiName()
        end
    end)

    -- Adaptive size (PC / mobile) ---------------------------------
    local vp = screenSize()
    local width = math.clamp(vp.X - 30, 300, opts.Width or 540)
    local height = math.clamp(vp.Y - 60, 220, opts.Height or 360)
    local sidebarW = width < 440 and 96 or 130
    local TOPBAR = 38

    local main = new("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2)),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Theme.Main,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = gui,
    })
    corner(main, 10)
    stroke(main, Theme.Outline, 1)
    local mainScale = new("UIScale", { Scale = 1, Parent = main })

    -- Top bar (drag here) ------------------------------------
    local topbar = new("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, TOPBAR),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = main,
    })
    new("Frame", { -- accent line
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = topbar,
    })
    new("Frame", { -- divider
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = topbar,
    })

    new("ImageLabel", {
        Position = UDim2.new(0, 10, 0.5, -10),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        Image = iconId,
        ScaleType = Enum.ScaleType.Fit,
        Parent = topbar,
    })
    label({
        Position = UDim2.new(0, 38, 0, 2),
        Size = UDim2.new(1, -110, 1, -2),
        Font = Enum.Font.GothamBold,
        RichText = true,
        Text = title .. (subtitle ~= "" and ('  <font color="#96A0AF" size="11">' .. subtitle .. "</font>") or ""),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = topbar,
    })

    local function topButton(text, xOffset, hoverColor)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, xOffset, 0.5, 1),
            Size = UDim2.fromOffset(28, 26),
            BackgroundColor3 = Theme.Element,
            AutoButtonColor = false,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 16,
            TextColor3 = Theme.Text,
            Parent = topbar,
        })
        corner(b, 6)
        hover(b, Theme.Element, hoverColor)
        return b
    end
    local minBtn = topButton("–", -42, Theme.Hover)
    local closeBtn = topButton("×", -8, Color3.fromRGB(200, 55, 65))

    -- Sidebar + pages ------------------------------------------------
    local sidebar = new("ScrollingFrame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, TOPBAR),
        Size = UDim2.new(0, sidebarW, 1, -TOPBAR),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = main,
    })
    padding(sidebar, 6, 8, 6, 8)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
    new("Frame", { -- right border
        Position = UDim2.new(0, sidebarW - 1, 0, TOPBAR),
        Size = UDim2.new(0, 1, 1, -TOPBAR),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = main,
    })

    local pages = new("Frame", {
        Name = "Pages",
        Position = UDim2.fromOffset(sidebarW, TOPBAR),
        Size = UDim2.new(1, -sidebarW, 1, -TOPBAR),
        BackgroundTransparency = 1,
        Parent = main,
    })

    -- Notifications -----------------------------------------------------
    local notifyHolder = new("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -12),
        Size = UDim2.new(0, 250, 1, -24),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Parent = notifyHolder,
    })
    local notifyCount = 0

    function Window:Notify(o)
        o = o or {}
        notifyCount = notifyCount + 1
        local card = new("CanvasGroup", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Main,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            LayoutOrder = notifyCount,
            Parent = notifyHolder,
        })
        corner(card, 8)
        stroke(card, Theme.Outline, 1)
        new("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Parent = card,
        })
        local inner = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = card,
        })
        padding(inner, 14, 8, 10, 8)
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
        label({
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.GothamBold,
            Text = o.Title or title,
            Parent = inner,
        })
        label({
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = o.Content or "",
            Parent = inner,
        })

        tween(card, 0.25, { GroupTransparency = 0 })
        task.delay(o.Duration or 4, function()
            if not card.Parent then return end
            local t = tween(card, 0.3, { GroupTransparency = 1 })
            t.Completed:Connect(function() card:Destroy() end)
        end)
    end

    -- Floating button (logo) — shown when minimized ---------------------
    local float = new("ImageButton", {
        Name = "FloatButton",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(math.floor(vp.X - 50), 110),
        Size = UDim2.fromOffset(54, 54),
        BackgroundColor3 = Theme.Background,
        AutoButtonColor = false,
        Active = true,
        Visible = false,
        ZIndex = 100,
        Parent = gui,
    })
    corner(float, 27)
    stroke(float, Theme.Accent, 2)
    local floatScale = new("UIScale", { Scale = 0, Parent = float })
    new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -16, 1, -16),
        BackgroundTransparency = 1,
        Image = iconId,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 101,
        Parent = float,
    })

    -- Clamp (keeps everything on screen) --------------------------------
    local function clampMain(x, y)
        local v = screenSize()
        x = math.clamp(x, 60, math.max(60, v.X - 60))
        y = math.clamp(y, height / 2, math.max(height / 2, v.Y - 40 + height / 2))
        return x, y
    end
    local function clampFloat(x, y)
        local v = screenSize()
        x = math.clamp(x, 27, math.max(27, v.X - 27))
        y = math.clamp(y, 27, math.max(27, v.Y - 27))
        return x, y
    end

    -- Minimize / restore ---------------------------------------------
    function Window:SetMinimized(state)
        if self._destroyed or self.Minimized == state then return end
        self.Minimized = state

        if state then
            local t = tween(mainScale, 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
            t.Completed:Connect(function(ps)
                if ps == Enum.PlaybackState.Completed and self.Minimized then main.Visible = false end
            end)
            if self.FloatEnabled then
                float.Visible = true
                floatScale.Scale = 0
                tween(floatScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            end
        else
            local x, y = clampMain(main.Position.X.Offset, main.Position.Y.Offset)
            main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            main.Visible = true
            tween(mainScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            if float.Visible then
                local t = tween(floatScale, 0.15, { Scale = 0 })
                t.Completed:Connect(function(ps)
                    if ps == Enum.PlaybackState.Completed and not self.Minimized then float.Visible = false end
                end)
            end
        end
    end

    function Window:Toggle() self:SetMinimized(not self.Minimized) end
    function Window:Minimize() self:SetMinimized(true) end
    function Window:Restore() self:SetMinimized(false) end

    function Window:SetToggleKey(key)
        if typeof(key) == "EnumItem" then self.ToggleKey = key end
    end

    function Window:SetFloatButton(enabled)
        self.FloatEnabled = enabled and true or false
        if self.Minimized then
            float.Visible = self.FloatEnabled
            floatScale.Scale = self.FloatEnabled and 1 or 0
        end
    end

    function Window:Destroy()
        Library:Unload()
    end

    -- Events -------------------------------------------------------------
    makeDraggable(topbar, main, clampMain)
    makeDraggable(float, float, clampFloat, function() Window:SetMinimized(false) end)

    connect(minBtn.MouseButton1Click, function()
        Window:SetMinimized(true)
        if not Window.FloatEnabled then
            Window:Notify({
                Title = title,
                Content = "Minimized. Press " .. Window.ToggleKey.Name .. " to open again.",
                Duration = 3,
            })
        end
    end)
    connect(closeBtn.MouseButton1Click, function()
        fire(opts.OnClose)
        Library:Unload()
    end)

    -- LeftControl (or the configured key) minimizes/restores
    connect(UIS.InputBegan, function(input)
        if Window._destroyed or Library.Listening then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if input.KeyCode == Window.ToggleKey and not UIS:GetFocusedTextBox() then
            Window:Toggle()
        end
    end)

    -- Tabs -------------------------------------------------------------------
    function Window:AddTab(name)
        local tab = { Name = name }

        local btn = new("TextButton", {
            LayoutOrder = #Window.Tabs + 1,
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = Theme.Element,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = name,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = sidebar,
        })
        corner(btn, 6)
        padding(btn, 14, 0, 6, 0)
        local indicator = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, -9, 0.5, 0),
            Size = UDim2.fromOffset(3, 16),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = false,
            Parent = btn,
        })
        corner(indicator, 2)

        local page = new("ScrollingFrame", {
            Name = name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Accent,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            Parent = pages,
        })
        padding(page, 10, 10, 12, 10)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })

        tab._btn, tab._page, tab._indicator = btn, page, indicator

        function tab:Select()
            for _, t in ipairs(Window.Tabs) do
                local on = (t == self)
                t._page.Visible = on
                t._indicator.Visible = on
                tween(t._btn, 0.15, {
                    BackgroundTransparency = on and 0 or 1,
                    TextColor3 = on and Theme.Text or Theme.SubText,
                })
            end
        end

        local tabCtx = { container = page, scroller = page, order = 0 }
        attach(tab, tabCtx)

        function tab:AddSection(secName)
            local frame = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Section,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(tabCtx),
                Parent = page,
            })
            corner(frame, 8)
            stroke(frame, Theme.Outline, 1)
            padding(frame, 8, 8, 8, 8)
            new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
            label({
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, 16),
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Accent,
                Text = string.upper(secName or "Section"),
                Parent = frame,
            })
            local section = {}
            attach(section, { container = frame, scroller = page, order = 0 })
            return section
        end

        connect(btn.MouseButton1Click, function() tab:Select() end)

        Window.Tabs[#Window.Tabs + 1] = tab
        if #Window.Tabs == 1 then tab:Select() end
        return tab
    end

    Library.Windows[#Library.Windows + 1] = Window
    Library.CurrentWindow = Window
    return Window
end

function Library:Notify(o)
    if self.CurrentWindow then self.CurrentWindow:Notify(o) end
end

-- Removes the UI and disconnects everything
function Library:Unload()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    for _, w in ipairs(Library.Windows) do
        w._destroyed = true
        pcall(function() w.Gui:Destroy() end)
    end
    table.clear(Library.Windows)
    Library.CurrentWindow = nil
    Library.Listening = false
    env.AzureUI_Cleanup = nil
end

env.AzureUI_Cleanup = function() Library:Unload() end

----------------------------------------------------------------------
-- USAGE EXAMPLE (you can delete from here down)
----------------------------------------------------------------------
--[[
local Window = Library:CreateWindow({
    Title = "azure.lol",
    Subtitle = "v1.0",
    Icon = 127041730095194,          -- your logo
    ToggleKey = Enum.KeyCode.LeftControl,
    -- FloatButton = true,           -- forces the logo button on PC too
})

local Principal = Window:AddTab("Main")

local geral = Principal:AddSection("General")
geral:AddToggle({
    Name = "Enable feature",
    Default = false,
    Callback = function(v) print("Toggle:", v) end,
})
geral:AddSlider({
    Name = "Speed",
    Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
    Callback = function(v) print("Slider:", v) end,
})
geral:AddDropdown({
    Name = "Mode",
    Options = { "Normal", "Fast", "Safe" },
    Default = "Normal",
    Callback = function(v) print("Mode:", v) end,
})
geral:AddButton({
    Name = "Show notification",
    Callback = function()
        Window:Notify({ Title = "azure.lol", Content = "Working perfectly!", Duration = 3 })
    end,
})

local extra = Principal:AddSection("Extras")
extra:AddTextbox({
    Name = "Name",
    Placeholder = "type here",
    Callback = function(text, enter) print("Text:", text, enter) end,
})
extra:AddLabel("Drag by the top bar. LeftControl minimizes/restores.")

local Config = Window:AddTab("Config")
local menu = Config:AddSection("Menu")
menu:AddKeybind({
    Name = "Menu key",
    Default = Enum.KeyCode.LeftControl,
    Changed = function(key) if key then Window:SetToggleKey(key) end end,
})
menu:AddToggle({
    Name = "Logo button on minimize",
    Default = Window.FloatEnabled,
    Callback = function(v) Window:SetFloatButton(v) end,
})
menu:AddButton({
    Name = "Unload UI",
    Callback = function() Library:Unload() end,
})

Window:Notify({ Title = "azure.lol", Content = "UI loaded! LeftControl minimizes.", Duration = 4 })
]]
return Library
