--[[
    AzureUI 2.0 — custom Roblox / Luau UI

    100% compatible with the old API (CreateWindow / AddTab / AddSection / AddToggle ...).

    WINDOW
      • Drag the top bar (mouse and touch). Drag the bottom-right corner to resize.
      • LeftControl minimizes. The round logo brings the window back.
      • Window:Notify({Title, Content, Duration, Type = "info"|"success"|"warning"|"error", Icon})
      • Window:Dialog({Title, Content, Buttons = {{Name, Callback}}})
      • Window:AddTabSection("Text")  -- small group header in the sidebar
      • Window:AddSettingsTab()       -- config save/load + menu key + accent color
      • Window:TryAutoLoad()          -- call after the UI is built

    TABS      Window:AddTab("Name", "home")  -- Lucide name or Roblox asset id
              tab:SetIcon("settings")  tab:ClearIcon()  tab:SetName("New")  tab:Destroy()

    ELEMENTS  AddLabel AddParagraph AddDivider AddButton AddToggle AddSlider
              AddDropdown (Multi / Search) AddTextbox AddKeybind AddColorPicker
              Every element has :Destroy(). Sections too (AddSection(name, {Collapsed, Closeable})).

    KEY SYSTEM
      local ok, key = Library:KeySystem({
          Title = "My Hub", Subtitle = "key required",
          Provider = "Luarmor",            -- Luarmor | Platoboost | Static | Custom | Http | (your own)
          ScriptId = "xxxxxxxx",           -- Luarmor
          -- Service = 1234, Secret = "...",-- Platoboost
          -- Keys = {"KEY-1","KEY-2"},     -- Static
          -- Validate = function(key, hwid) return true, "ok" end, -- Custom
          Discord = "https://discord.gg/xxxx",
      })
      if not ok then return end
      -- or just: Library:CreateWindow({ ..., KeySystem = { ... } })  (returns nil if the key fails)
      See Library:RegisterKeyProvider(name, {Validate=..., GetLink=...}) to add your own method.
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
    Background  = Color3.fromRGB(9, 11, 17),
    Main        = Color3.fromRGB(14, 17, 26),
    Section     = Color3.fromRGB(17, 21, 31),
    Element     = Color3.fromRGB(23, 28, 41),
    Hover       = Color3.fromRGB(31, 38, 56),
    Outline     = Color3.fromRGB(38, 46, 66),
    Accent      = Color3.fromRGB(64, 156, 255),
    AccentDark  = Color3.fromRGB(41, 101, 166),
    Text        = Color3.fromRGB(240, 243, 250),
    SubText     = Color3.fromRGB(133, 143, 164),
    Success     = Color3.fromRGB(52, 211, 153),
    Warning     = Color3.fromRGB(251, 191, 36),
    Danger      = Color3.fromRGB(248, 113, 113),
}

local Library = {
    Version = "2.0",
    Theme = Theme,
    Windows = {},
    Flags = {},
    Listening = false, -- true while a Keybind is waiting for a key
    KeyProviders = {},
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

-- Accent color registry: anything registered here recolors when Library:SetAccent() runs
local accentFns = {}

local function onAccent(fn)
    accentFns[#accentFns + 1] = fn
    pcall(fn, Theme.Accent)
    return fn
end

local function accentize(inst, prop)
    onAccent(function(c) inst[prop] = c end)
end

local function darken(c, amount)
    return c:Lerp(Color3.new(0, 0, 0), amount or 0.38)
end

local function accentGradient(inst, rotation)
    local g = new("UIGradient", {
        Rotation = rotation or 0,
        Color = ColorSequence.new(Theme.Accent, Theme.AccentDark),
        Parent = inst,
    })
    onAccent(function(c) g.Color = ColorSequence.new(c, darken(c)) end)
    return g
end

local function dropShadow(parent, spread, transparency)
    return new("ImageLabel", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, spread * 2, 1, spread * 2),
        BackgroundTransparency = 1,
        Image = "rbxassetid://6014261993",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = transparency or 0.5,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = parent,
    })
end

function Library:SetAccent(color)
    if typeof(color) ~= "Color3" then return end
    Theme.Accent = color
    Theme.AccentDark = darken(color)
    for _, fn in ipairs(accentFns) do pcall(fn, color) end
end

-- Merge colors into the theme. Accent updates live; other colors apply to new objects.
function Library:SetTheme(t)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if k ~= "Accent" and typeof(v) == "Color3" then Theme[k] = v end
    end
    if typeof(t.Accent) == "Color3" then self:SetAccent(t.Accent) end
end

Library.Icons = {
	accessibility = 10709751939,
	activity = 10709752035,
	airvent = 10709752131,
	airplay = 10709752254,
	alarmcheck = 10709752405,
	alarmclock = 10709752630,
	alarmclockoff = 10709752508,
	alarmminus = 10709752732,
	alarmplus = 10709752825,
	album = 10709752906,
	alertcircle = 10709752996,
	alertoctagon = 10709753064,
	alerttriangle = 10709753149,
	aligncenter = 10709753570,
	aligncenterhorizontal = 10709753272,
	aligncentervertical = 10709753421,
	alignendhorizontal = 10709753692,
	alignendvertical = 10709753808,
	alignhorizontaldistributecenter = 10747779791,
	alignhorizontaldistributeend = 10747784534,
	alignhorizontaldistributestart = 10709754118,
	alignhorizontaljustifycenter = 10709754204,
	alignhorizontaljustifyend = 10709754317,
	alignhorizontaljustifystart = 10709754436,
	alignhorizontalspacearound = 10709754590,
	alignhorizontalspacebetween = 10709754749,
	alignjustify = 10709759610,
	alignleft = 10709759764,
	alignright = 10709759895,
	alignstarthorizontal = 10709760051,
	alignstartvertical = 10709760244,
	alignverticaldistributecenter = 10709760351,
	alignverticaldistributeend = 10709760434,
	alignverticaldistributestart = 10709760612,
	alignverticaljustifycenter = 10709760814,
	alignverticaljustifyend = 10709761003,
	alignverticaljustifystart = 10709761176,
	alignverticalspacearound = 10709761324,
	alignverticalspacebetween = 10709761434,
	anchor = 10709761530,
	angry = 10709761629,
	annoyed = 10709761722,
	aperture = 10709761813,
	apple = 10709761889,
	archive = 10709762233,
	archiverestore = 10709762058,
	armchair = 10709762327,
	arrowbigdown = 10747796644,
	arrowbigleft = 10709762574,
	arrowbigright = 10709762727,
	arrowbigup = 10709762879,
	arrowdown = 10709767827,
	arrowdowncircle = 10709763034,
	arrowdownleft = 10709767656,
	arrowdownright = 10709767750,
	arrowleft = 10709768114,
	arrowleftcircle = 10709767936,
	arrowleftright = 10709768019,
	arrowright = 10709768347,
	arrowrightcircle = 10709768226,
	arrowup = 10709768939,
	arrowupcircle = 10709768432,
	arrowupdown = 10709768538,
	arrowupleft = 10709768661,
	arrowupright = 10709768787,
	asterisk = 10709769095,
	atsign = 10709769286,
	award = 10709769406,
	axe = 10709769508,
	axis3d = 10709769598,
	baby = 10709769732,
	backpack = 10709769841,
	baggageclaim = 10709769935,
	banana = 10709770005,
	banknote = 10709770178,
	barchart = 10709773755,
	barchart2 = 10709770317,
	barchart3 = 10709770431,
	barchart4 = 10709770560,
	barcharthorizontal = 10709773669,
	barcode = 10747360675,
	baseline = 10709773863,
	bath = 10709773963,
	battery = 10709774640,
	batterycharging = 10709774068,
	batteryfull = 10709774206,
	batterylow = 10709774370,
	batterymedium = 10709774513,
	beaker = 10709774756,
	bed = 10709775036,
	beddouble = 10709774864,
	bedsingle = 10709774968,
	beer = 10709775167,
	bell = 10709775704,
	bellminus = 10709775241,
	belloff = 10709775320,
	bellplus = 10709775448,
	bellring = 10709775560,
	bike = 10709775894,
	binary = 10709776050,
	bitcoin = 10709776126,
	bluetooth = 10709776655,
	bluetoothconnected = 10709776240,
	bluetoothoff = 10709776344,
	bluetoothsearching = 10709776501,
	bold = 10747813908,
	bomb = 10709781460,
	bone = 10709781605,
	book = 10709781824,
	bookopen = 10709781717,
	bookmark = 10709782154,
	bookmarkminus = 10709781919,
	bookmarkplus = 10709782044,
	bot = 10709782230,
	box = 10709782497,
	boxselect = 10709782342,
	boxes = 10709782582,
	briefcase = 10709782662,
	brush = 10709782758,
	bug = 10709782845,
	building = 10709783051,
	building2 = 10709782939,
	bus = 10709783137,
	cake = 10709783217,
	calculator = 10709783311,
	calendar = 10709789505,
	calendarcheck = 10709783474,
	calendarcheck2 = 10709783392,
	calendarclock = 10709783577,
	calendardays = 10709783673,
	calendarheart = 10709783835,
	calendarminus = 10709783959,
	calendaroff = 10709788784,
	calendarplus = 10709788937,
	calendarrange = 10709789053,
	calendarsearch = 10709789200,
	calendarx = 10709789407,
	calendarx2 = 10709789329,
	camera = 10709789686,
	cameraoff = 10747822677,
	car = 10709789810,
	carrot = 10709789960,
	cast = 10709790097,
	charge = 10709790202,
	check = 10709790644,
	checkcircle = 10709790387,
	checkcircle2 = 10709790298,
	checksquare = 10709790537,
	chefhat = 10709790757,
	cherry = 10709790875,
	chevrondown = 10709790948,
	chevronfirst = 10709791015,
	chevronlast = 10709791130,
	chevronleft = 10709791281,
	chevronright = 10709791437,
	chevronup = 10709791523,
	chevronsdown = 10709796864,
	chevronsdownup = 10709791632,
	chevronsleft = 10709797151,
	chevronsleftright = 10709797006,
	chevronsright = 10709797382,
	chevronsrightleft = 10709797274,
	chevronsup = 10709797622,
	chevronsupdown = 10709797508,
	chrome = 10709797725,
	circle = 10709798174,
	circledot = 10709797837,
	circleellipsis = 10709797985,
	circleslashed = 10709798100,
	citrus = 10709798276,
	clapperboard = 10709798350,
	clipboard = 10709799288,
	clipboardcheck = 10709798443,
	clipboardcopy = 10709798574,
	clipboardedit = 10709798682,
	clipboardlist = 10709798792,
	clipboardsignature = 10709798890,
	clipboardtype = 10709798999,
	clipboardx = 10709799124,
	clock = 10709805144,
	clock1 = 10709799535,
	clock10 = 10709799718,
	clock11 = 10709799818,
	clock12 = 10709799962,
	clock2 = 10709803876,
	clock3 = 10709803989,
	clock4 = 10709804164,
	clock5 = 10709804291,
	clock6 = 10709804435,
	clock7 = 10709804599,
	clock8 = 10709804784,
	clock9 = 10709804996,
	cloud = 10709806740,
	cloudcog = 10709805262,
	clouddrizzle = 10709805371,
	cloudfog = 10709805477,
	cloudhail = 10709805596,
	cloudlightning = 10709805727,
	cloudmoon = 10709805942,
	cloudmoonrain = 10709805838,
	cloudoff = 10709806060,
	cloudrain = 10709806277,
	cloudrainwind = 10709806166,
	cloudsnow = 10709806374,
	cloudsun = 10709806631,
	cloudsunrain = 10709806475,
	cloudy = 10709806859,
	clover = 10709806995,
	code = 10709810463,
	code2 = 10709807111,
	codepen = 10709810534,
	codesandbox = 10709810676,
	coffee = 10709810814,
	cog = 10709810948,
	coins = 10709811110,
	columns = 10709811261,
	command = 10709811365,
	compass = 10709811445,
	component = 10709811595,
	conciergebell = 10709811706,
	connection = 10747361219,
	contact = 10709811834,
	contrast = 10709811939,
	cookie = 10709812067,
	copy = 10709812159,
	copyleft = 10709812251,
	copyright = 10709812311,
	cornerdownleft = 10709812396,
	cornerdownright = 10709812485,
	cornerleftdown = 10709812632,
	cornerleftup = 10709812784,
	cornerrightdown = 10709812939,
	cornerrightup = 10709813094,
	cornerupleft = 10709813185,
	cornerupright = 10709813281,
	cpu = 10709813383,
	croissant = 10709818125,
	crop = 10709818245,
	cross = 10709818399,
	crosshair = 10709818534,
	crown = 10709818626,
	cupsoda = 10709818763,
	curlybraces = 10709818847,
	currency = 10709818931,
	database = 10709818996,
	delete = 10709819059,
	diamond = 10709819149,
	dice1 = 10709819266,
	dice2 = 10709819361,
	dice3 = 10709819508,
	dice4 = 10709819670,
	dice5 = 10709819801,
	dice6 = 10709819896,
	dices = 10723343321,
	diff = 10723343416,
	disc = 10723343537,
	divide = 10723343805,
	dividecircle = 10723343636,
	dividesquare = 10723343737,
	dollarsign = 10723343958,
	download = 10723344270,
	downloadcloud = 10723344088,
	droplet = 10723344432,
	droplets = 10734883356,
	drumstick = 10723344737,
	edit = 10734883598,
	edit2 = 10723344885,
	edit3 = 10723345088,
	egg = 10723345518,
	eggfried = 10723345347,
	electricity = 10723345749,
	electricityoff = 10723345643,
	equal = 10723345990,
	equalnot = 10723345866,
	eraser = 10723346158,
	euro = 10723346372,
	expand = 10723346553,
	externallink = 10723346684,
	eye = 10723346959,
	eyeoff = 10723346871,
	factory = 10723347051,
	fan = 10723354359,
	fastforward = 10723354521,
	feather = 10723354671,
	figma = 10723354801,
	file = 10723374641,
	filearchive = 10723354921,
	fileaudio = 10723355148,
	fileaudio2 = 10723355026,
	fileaxis3d = 10723355272,
	filebadge = 10723355622,
	filebadge2 = 10723355451,
	filebarchart = 10723355887,
	filebarchart2 = 10723355746,
	filebox = 10723355989,
	filecheck = 10723356210,
	filecheck2 = 10723356100,
	fileclock = 10723356329,
	filecode = 10723356507,
	filecog = 10723356830,
	filecog2 = 10723356676,
	filediff = 10723357039,
	filedigit = 10723357151,
	filedown = 10723357322,
	fileedit = 10723357495,
	fileheart = 10723357637,
	fileimage = 10723357790,
	fileinput = 10723357933,
	filejson = 10723364435,
	filejson2 = 10723364361,
	filekey = 10723364605,
	filekey2 = 10723364515,
	filelinechart = 10723364725,
	filelock = 10723364957,
	filelock2 = 10723364861,
	fileminus = 10723365254,
	fileminus2 = 10723365086,
	fileoutput = 10723365457,
	filepiechart = 10723365598,
	fileplus = 10723365877,
	fileplus2 = 10723365766,
	filequestion = 10723365987,
	filescan = 10723366167,
	filesearch = 10723366550,
	filesearch2 = 10723366340,
	filesignature = 10723366741,
	filespreadsheet = 10723366962,
	filesymlink = 10723367098,
	fileterminal = 10723367244,
	filetext = 10723367380,
	filetype = 10723367606,
	filetype2 = 10723367509,
	fileup = 10723367734,
	filevideo = 10723373884,
	filevideo2 = 10723367834,
	filevolume = 10723374172,
	filevolume2 = 10723374030,
	filewarning = 10723374276,
	filex = 10723374544,
	filex2 = 10723374378,
	files = 10723374759,
	film = 10723374981,
	filter = 10723375128,
	fingerprint = 10723375250,
	fish = 127664059821666,
	flag = 10723375890,
	flagoff = 10723375443,
	flagtriangleleft = 10723375608,
	flagtriangleright = 10723375727,
	flame = 10723376114,
	flashlight = 10723376471,
	flashlightoff = 10723376365,
	flaskconical = 10734883986,
	flaskround = 10723376614,
	fliphorizontal = 10723376884,
	fliphorizontal2 = 10723376745,
	flipvertical = 10723377138,
	flipvertical2 = 10723377026,
	flower = 10747830374,
	flower2 = 10723377305,
	focus = 10723377537,
	folder = 10723387563,
	folderarchive = 10723384478,
	foldercheck = 10723384605,
	folderclock = 10723384731,
	folderclosed = 10723384893,
	foldercog = 10723385213,
	foldercog2 = 10723385036,
	folderdown = 10723385338,
	folderedit = 10723385445,
	folderheart = 10723385545,
	folderinput = 10723385721,
	folderkey = 10723385848,
	folderlock = 10723386005,
	folderminus = 10723386127,
	folderopen = 10723386277,
	folderoutput = 10723386386,
	folderplus = 10723386531,
	foldersearch = 10723386787,
	foldersearch2 = 10723386674,
	foldersymlink = 10723386930,
	foldertree = 10723387085,
	folderup = 10723387265,
	folderx = 10723387448,
	folders = 10723387721,
	forminput = 10723387841,
	forward = 10723388016,
	frame = 10723394389,
	framer = 10723394565,
	frown = 10723394681,
	fuel = 10723394846,
	functionsquare = 10723395041,
	gamepad = 10723395457,
	gamepad2 = 10723395215,
	gauge = 10723395708,
	gavel = 10723395896,
	gem = 10723396000,
	ghost = 10723396107,
	gift = 10723396402,
	giftcard = 10723396225,
	gitbranch = 10723396676,
	gitbranchplus = 10723396542,
	gitcommit = 10723396812,
	gitcompare = 10723396954,
	gitfork = 10723397049,
	gitmerge = 10723397165,
	gitpullrequest = 10723397431,
	gitpullrequestclosed = 10723397268,
	gitpullrequestdraft = 10734884302,
	glass = 10723397788,
	glass2 = 10723397529,
	glasswater = 10723397678,
	glasses = 10723397895,
	globe = 10723404337,
	globe2 = 10723398002,
	grab = 10723404472,
	graduationcap = 10723404691,
	grape = 10723404822,
	grid = 10723404936,
	griphorizontal = 10723405089,
	gripvertical = 10723405236,
	hammer = 10723405360,
	hand = 10723405649,
	handmetal = 10723405508,
	harddrive = 10723405749,
	hardhat = 10723405859,
	hash = 10723405975,
	haze = 10723406078,
	headphones = 10723406165,
	heart = 10723406885,
	heartcrack = 10723406299,
	hearthandshake = 10723406480,
	heartoff = 10723406662,
	heartpulse = 10723406795,
	helpcircle = 10723406988,
	hexagon = 10723407092,
	highlighter = 10723407192,
	history = 10723407335,
	home = 10723407389,
	hourglass = 10723407498,
	icecream = 10723414308,
	image = 10723415040,
	imageminus = 10723414487,
	imageoff = 10723414677,
	imageplus = 10723414827,
	import = 10723415205,
	inbox = 10723415335,
	indent = 10723415494,
	indianrupee = 10723415642,
	infinity = 10723415766,
	info = 10723415903,
	inspect = 10723416057,
	italic = 10723416195,
	japaneseyen = 10723416363,
	joystick = 10723416527,
	key = 10723416652,
	keyboard = 10723416765,
	lamp = 10723417513,
	lampceiling = 10723416922,
	lampdesk = 10723417016,
	lampfloor = 10723417131,
	lampwalldown = 10723417240,
	lampwallup = 10723417356,
	landmark = 10723417608,
	languages = 10723417703,
	laptop = 10723423881,
	laptop2 = 10723417797,
	lasso = 10723424235,
	lassoselect = 10723424058,
	laugh = 10723424372,
	layers = 10723424505,
	layout = 10723425376,
	layoutdashboard = 10723424646,
	layoutgrid = 10723424838,
	layoutlist = 10723424963,
	layouttemplate = 10723425187,
	leaf = 10723425539,
	library = 10723425615,
	lifebuoy = 10723425685,
	lightbulb = 10723425852,
	lightbulboff = 10723425762,
	linechart = 10723426393,
	link = 10723426722,
	link2 = 10723426595,
	link2off = 10723426513,
	list = 10723433811,
	listchecks = 10734884548,
	listend = 10723426886,
	listminus = 10723426986,
	listmusic = 10723427081,
	listordered = 10723427199,
	listplus = 10723427334,
	liststart = 10723427494,
	listvideo = 10723427619,
	listx = 10723433655,
	loader = 10723434070,
	loader2 = 10723433935,
	locate = 10723434557,
	locatefixed = 10723434236,
	locateoff = 10723434379,
	lock = 10723434711,
	login = 10723434830,
	logout = 10723434906,
	luggage = 10723434993,
	magnet = 10723435069,
	mail = 10734885430,
	mailcheck = 10723435182,
	mailminus = 10723435261,
	mailopen = 10723435342,
	mailplus = 10723435443,
	mailquestion = 10723435515,
	mailsearch = 10734884739,
	mailwarning = 10734885015,
	mailx = 10734885247,
	mails = 10734885614,
	map = 10734886202,
	mappin = 10734886004,
	mappinoff = 10734885803,
	maximize = 10734886735,
	maximize2 = 10734886496,
	medal = 10734887072,
	megaphone = 10734887454,
	megaphoneoff = 10734887311,
	meh = 10734887603,
	menu = 10734887784,
	messagecircle = 10734888000,
	messagesquare = 10734888228,
	mic = 10734888864,
	mic2 = 10734888430,
	micoff = 10734888646,
	microscope = 10734889106,
	microwave = 10734895076,
	milestone = 10734895310,
	minimize = 10734895698,
	minimize2 = 10734895530,
	minus = 10734896206,
	minuscircle = 10734895856,
	minussquare = 10734896029,
	monitor = 10734896881,
	monitoroff = 10734896360,
	monitorspeaker = 10734896512,
	moon = 10734897102,
	morehorizontal = 10734897250,
	morevertical = 10734897387,
	mountain = 10734897956,
	mountainsnow = 10734897665,
	mouse = 10734898592,
	mousepointer = 10734898476,
	mousepointer2 = 10734898194,
	mousepointerclick = 10734898355,
	move = 10734900011,
	move3d = 10734898756,
	movediagonal = 10734899164,
	movediagonal2 = 10734898934,
	movehorizontal = 10734899414,
	movevertical = 10734899821,
	music = 10734905958,
	music2 = 10734900215,
	music3 = 10734905665,
	music4 = 10734905823,
	navigation = 10734906744,
	navigation2 = 10734906332,
	navigation2off = 10734906144,
	navigationoff = 10734906580,
	network = 10734906975,
	newspaper = 10734907168,
	octagon = 10734907361,
	option = 10734907649,
	outdent = 10734907933,
	package = 10734909540,
	package2 = 10734908151,
	packagecheck = 10734908384,
	packageminus = 10734908626,
	packageopen = 10734908793,
	packageplus = 10734909016,
	packagesearch = 10734909196,
	packagex = 10734909375,
	paintbucket = 10734909847,
	paintbrush = 10734910187,
	paintbrush2 = 10734910030,
	palette = 10734910430,
	palmtree = 10734910680,
	paperclip = 10734910927,
	partypopper = 10734918735,
	pause = 10734919336,
	pausecircle = 10735024209,
	pauseoctagon = 10734919143,
	pentool = 10734919503,
	pencil = 10734919691,
	percent = 10734919919,
	personstanding = 10734920149,
	phone = 10734921524,
	phonecall = 10734920305,
	phoneforwarded = 10734920508,
	phoneincoming = 10734920694,
	phonemissed = 10734920845,
	phoneoff = 10734921077,
	phoneoutgoing = 10734921288,
	piechart = 10734921727,
	piggybank = 10734921935,
	pin = 10734922324,
	pinoff = 10734922180,
	pipette = 10734922497,
	pizza = 10734922774,
	plane = 10734922971,
	play = 10734923549,
	playcircle = 10734923214,
	plus = 10734924532,
	pluscircle = 10734923868,
	plussquare = 10734924219,
	podcast = 10734929553,
	pointer = 10734929723,
	poundsterling = 10734929981,
	power = 10734930466,
	poweroff = 10734930257,
	printer = 10734930632,
	puzzle = 10734930886,
	quote = 10734931234,
	radio = 10734931596,
	radioreceiver = 10734931402,
	rectanglehorizontal = 10734931777,
	rectanglevertical = 10734932081,
	recycle = 10734932295,
	redo = 10734932822,
	redo2 = 10734932586,
	refreshccw = 10734933056,
	refreshcw = 10734933222,
	refrigerator = 10734933465,
	regex = 10734933655,
	["repeat"] = 10734933966,
	repeat1 = 10734933826,
	reply = 10734934252,
	replyall = 10734934132,
	rewind = 10734934347,
	rocket = 10734934585,
	rockingchair = 10734939942,
	rotate3d = 10734940107,
	rotateccw = 10734940376,
	rotatecw = 10734940654,
	rss = 10734940825,
	ruler = 10734941018,
	russianruble = 10734941199,
	sailboat = 10734941354,
	save = 10734941499,
	scale = 10734941912,
	scale3d = 10734941739,
	scaling = 10734942072,
	scan = 10734942565,
	scanface = 10734942198,
	scanline = 10734942351,
	scissors = 10734942778,
	screenshare = 10734943193,
	screenshareoff = 10734942967,
	scroll = 10734943448,
	search = 10734943674,
	send = 10734943902,
	separatorhorizontal = 10734944115,
	separatorvertical = 10734944326,
	server = 10734949856,
	servercog = 10734944444,
	servercrash = 10734944554,
	serveroff = 10734944668,
	settings = 10734950309,
	settings2 = 10734950020,
	share = 10734950813,
	share2 = 10734950553,
	sheet = 10734951038,
	shield = 10734951847,
	shieldalert = 10734951173,
	shieldcheck = 10734951367,
	shieldclose = 10734951535,
	shieldoff = 10734951684,
	shirt = 10734952036,
	shoppingbag = 10734952273,
	shoppingcart = 10734952479,
	shovel = 10734952773,
	showerhead = 10734952942,
	shrink = 10734953073,
	shrub = 10734953241,
	shuffle = 10734953451,
	sidebar = 10734954301,
	sidebarclose = 10734953715,
	sidebaropen = 10734954000,
	sigma = 10734954538,
	signal = 10734961133,
	signalhigh = 10734954807,
	signallow = 10734955080,
	signalmedium = 10734955336,
	signalzero = 10734960878,
	siren = 10734961284,
	skipback = 10734961526,
	skipforward = 10734961809,
	skull = 10734962068,
	slack = 10734962339,
	slash = 10734962600,
	slice = 10734963024,
	sliders = 10734963400,
	slidershorizontal = 10734963191,
	smartphone = 10734963940,
	smartphonecharging = 10734963671,
	smile = 10734964441,
	smileplus = 10734964188,
	snowflake = 10734964600,
	sofa = 10734964852,
	sortasc = 10734965115,
	sortdesc = 10734965287,
	speaker = 10734965419,
	sprout = 10734965572,
	square = 10734965702,
	star = 10734966248,
	starhalf = 10734965897,
	staroff = 10734966097,
	stethoscope = 10734966384,
	sticker = 10734972234,
	stickynote = 10734972463,
	stopcircle = 10734972621,
	stretchhorizontal = 10734972862,
	stretchvertical = 10734973130,
	strikethrough = 10734973290,
	subscript = 10734973457,
	sun = 10734974297,
	sundim = 10734973645,
	sunmedium = 10734973778,
	sunmoon = 10734973999,
	sunsnow = 10734974130,
	sunrise = 10734974522,
	sunset = 10734974689,
	superscript = 10734974850,
	swissfranc = 10734975024,
	switchcamera = 10734975214,
	sword = 10734975486,
	swords = 10734975692,
	syringe = 10734975932,
	table = 10734976230,
	table2 = 10734976097,
	tablet = 10734976394,
	tag = 10734976528,
	tags = 10734976739,
	target = 10734977012,
	tent = 10734981750,
	terminal = 10734982144,
	terminalsquare = 10734981995,
	textcursor = 10734982395,
	textcursorinput = 10734982297,
	thermometer = 10734983134,
	thermometersnowflake = 10734982571,
	thermometersun = 10734982771,
	thumbsdown = 10734983359,
	thumbsup = 10734983629,
	ticket = 10734983868,
	timer = 10734984606,
	timeroff = 10734984138,
	timerreset = 10734984355,
	toggleleft = 10734984834,
	toggleright = 10734985040,
	tornado = 10734985247,
	toybrick = 10747361919,
	train = 10747362105,
	trash = 10747362393,
	trash2 = 10747362241,
	treedeciduous = 10747362534,
	treepine = 10747362748,
	trees = 10747363016,
	trendingdown = 10747363205,
	trendingup = 10747363465,
	triangle = 10747363621,
	trophy = 10747363809,
	truck = 10747364031,
	tv = 10747364593,
	tv2 = 10747364302,
	type = 10747364761,
	umbrella = 10747364971,
	underline = 10747365191,
	undo = 10747365484,
	undo2 = 10747365359,
	unlink = 10747365771,
	unlink2 = 10747397871,
	unlock = 10747366027,
	upload = 10747366434,
	uploadcloud = 10747366266,
	usb = 10747366606,
	user = 10747373176,
	usercheck = 10747371901,
	usercog = 10747372167,
	userminus = 10747372346,
	userplus = 10747372702,
	userx = 10747372992,
	users = 10747373426,
	utensils = 10747373821,
	utensilscrossed = 10747373629,
	venetianmask = 10747374003,
	verified = 10747374131,
	vibrate = 10747374489,
	vibrateoff = 10747374269,
	video = 10747374938,
	videooff = 10747374721,
	view = 10747375132,
	voicemail = 10747375281,
	volume = 10747376008,
	volume1 = 10747375450,
	volume2 = 10747375679,
	volumex = 10747375880,
	wallet = 10747376205,
	wand = 10747376565,
	wand2 = 10747376349,
	watch = 10747376722,
	waves = 10747376931,
	webcam = 10747381992,
	wifi = 10747382504,
	wifioff = 10747382268,
	wind = 10747382750,
	wraptext = 10747383065,
	wrench = 10747383470,
	x = 10747384394,
	xcircle = 10747383819,
	xoctagon = 10747384037,
	xsquare = 10747384217,
	zoomin = 10747384552,
	zoomout = 10747384679
}

local function resolveIcon(icon)
    if icon == nil or icon == false or icon == "" then return nil end
    if type(icon) == "number" then
        if icon <= 0 then return nil end
        return "rbxassetid://" .. tostring(math.floor(icon))
    end
    if type(icon) ~= "string" then return nil end

    if icon:match("^rbxassetid://") or icon:match("^rbxasset://") then
        return icon
    end
    local digits = icon:match("^%s*(%d+)%s*$")
    if digits then return "rbxassetid://" .. digits end

    local key = string.lower(icon)
    key = key:gsub("^lucide:", ""):gsub("^icon:", "")
    key = key:gsub("[%s%-_]", "")
    local id = Library.Icons[key]
    if id then return "rbxassetid://" .. tostring(id) end
    warn("[AzureUI] icon not found: " .. icon)
    return nil
end
Library.ResolveIcon = resolveIcon

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

-- "XXXXX-XXXXXX-XXXXX"
local function randomGuiName()
    return randomSegment(5) .. "-" .. randomSegment(6) .. "-" .. randomSegment(5)
end

local function screenSize()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1280, 720)
end

local function getGuiParent()
    local okHui, hui = pcall(function() return gethui and gethui() end)
    if okHui and typeof(hui) == "Instance" then return hui end
    local okCore = pcall(function() return game:GetService("CoreGui"):GetChildren() end)
    if okCore then return game:GetService("CoreGui") end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function protectGui(gui)
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

----------------------------------------------------------------------
-- MOBILE + CONFIG
----------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local MOBILE = UIS.TouchEnabled and not UIS.MouseEnabled
local CONFIG_FOLDER = "AzureUI"

local function rowH()
    return MOBILE and 44 or 36
end

local function hasFS()
    return type(writefile) == "function" and type(readfile) == "function"
end

local function ensureFolder(sub)
    if type(makefolder) ~= "function" then return end
    local function make(path)
        local exists = type(isfolder) == "function" and isfolder(path)
        if not exists then pcall(makefolder, path) end
    end
    make(CONFIG_FOLDER)
    if sub then make(CONFIG_FOLDER .. "/" .. sub) end
end

local function cleanConfigName(name, fallback)
    name = tostring(name or ""):gsub("[^%w%-]", "")
    if name == "" then return fallback or "" end
    return name
end

local function configPath(name)
    local clean = cleanConfigName(name, "default")
    if clean == "" then clean = "default" end
    return CONFIG_FOLDER .. "/" .. clean .. ".json", clean
end

local function bindRoot(obj, root)
    obj._root = root
    obj._dead = false
    function obj:Destroy()
        if self._dead then return end
        self._dead = true
        if self.Flag and Library.Flags[self.Flag] == self then
            Library.Flags[self.Flag] = nil
        end
        pcall(function()
            if root and root.Parent then root:Destroy() end
        end)
    end
end

local function bindFlag(obj, root, opts, kind)
    bindRoot(obj, root)
    if opts and opts.NoSave then
        obj._noSave = true
        return
    end
    local flag = opts and opts.Flag
    if flag == nil or flag == false or flag == "" then
        flag = (opts and (opts.Name or opts.Text)) or kind
    end
    flag = tostring(flag)
    local base, n = flag, 2
    while Library.Flags[flag] do
        flag = base .. "_" .. tostring(n)
        n = n + 1
    end
    obj.Flag = flag
    Library.Flags[flag] = obj
end

function Library:Serialize()
    local values = {}
    for flag, obj in pairs(self.Flags) do
        if obj.Get and not obj._dead and not obj._noSave then
            local v = obj:Get()
            if v == nil then
                values[flag] = { _nil = true }
            elseif typeof(v) == "EnumItem" then
                values[flag] = { _key = v.Name }
            elseif typeof(v) == "Color3" then
                values[flag] = { _c3 = {
                    math.floor(v.R * 255 + 0.5),
                    math.floor(v.G * 255 + 0.5),
                    math.floor(v.B * 255 + 0.5),
                } }
            else
                values[flag] = v
            end
        end
    end
    return values
end

function Library:Apply(values)
    for flag, v in pairs(values or {}) do
        local obj = self.Flags[flag]
        if obj and obj.Set and not obj._dead then
            if type(v) == "table" and v._nil then
                obj:Set(nil, false)
            elseif type(v) == "table" and v._key then
                obj:Set(v._key, false)
            elseif type(v) == "table" and v._c3 then
                obj:Set(Color3.fromRGB(v._c3[1] or 255, v._c3[2] or 255, v._c3[3] or 255), false)
            else
                obj:Set(v, false)
            end
        end
    end
end

function Library:SaveConfig(name, windowState)
    local okEnc, json = pcall(function()
        return HttpService:JSONEncode({
            version = 1,
            values = self:Serialize(),
            window = windowState,
        })
    end)
    if not okEnc then
        warn("[AzureUI] save failed: " .. tostring(json))
        return false
    end
    local path, clean = configPath(name)
    if hasFS() then
        ensureFolder()
        local ok, err = pcall(writefile, path, json)
        if not ok then
            warn("[AzureUI] save failed: " .. tostring(err))
            return false
        end
    else
        env.AzureUI_Configs = env.AzureUI_Configs or {}
        env.AzureUI_Configs[clean] = json
    end
    return true, clean
end

function Library:LoadConfig(name)
    local path, clean = configPath(name)
    local json
    if hasFS() then
        local canRead = true
        if type(isfile) == "function" then
            local ok, exists = pcall(isfile, path)
            canRead = ok and exists or false
        end
        if canRead then
            local ok, data = pcall(readfile, path)
            if ok and type(data) == "string" then json = data end
        end
    end
    if not json and type(env.AzureUI_Configs) == "table" then
        json = env.AzureUI_Configs[clean]
    end
    if type(json) ~= "string" or json == "" then return false end
    local ok, payload = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not ok or type(payload) ~= "table" then return false end
    self:Apply(payload.values)
    return true, payload
end

function Library:DeleteConfig(name)
    local path, clean = configPath(name)
    if type(delfile) == "function" then pcall(delfile, path) end
    if type(env.AzureUI_Configs) == "table" then env.AzureUI_Configs[clean] = nil end
    return true, clean
end

function Library:ListConfigs()
    local seen, names = {}, {}
    local function add(n)
        n = cleanConfigName(n, "")
        if n ~= "" and not seen[n] then
            seen[n] = true
            names[#names + 1] = n
        end
    end
    if type(listfiles) == "function" then
        local ok, files = pcall(listfiles, CONFIG_FOLDER)
        if ok and type(files) == "table" then
            for _, f in ipairs(files) do
                local base = tostring(f):match("([^/\\]+)%.json$")
                if base then add(base) end
            end
        end
    end
    if type(env.AzureUI_Configs) == "table" then
        for n in pairs(env.AzureUI_Configs) do add(n) end
    end
    table.sort(names)
    if #names == 0 then names[1] = "default" end
    return names
end

function Library:GetAutoload()
    if hasFS() then
        local ok, data = pcall(readfile, CONFIG_FOLDER .. "/autoload.txt")
        if ok and type(data) == "string" then
            data = data:match("^%s*(.-)%s*$") or ""
            if data == "" then return "" end
            return cleanConfigName(data, "")
        end
    end
    if type(env.AzureUI_Autoload) == "string" and env.AzureUI_Autoload ~= "" then
        return cleanConfigName(env.AzureUI_Autoload, "")
    end
    return ""
end

function Library:SetAutoload(name)
    local clean = ""
    if name and name ~= false and name ~= "" then
        clean = cleanConfigName(name, "")
    end
    env.AzureUI_Autoload = clean
    if hasFS() then
        ensureFolder()
        pcall(writefile, CONFIG_FOLDER .. "/autoload.txt", clean)
    end
    return clean
end

----------------------------------------------------------------------
-- DRAGGING (mouse + touch)
-- handle  = element that receives the click/touch
-- target  = element that moves (AnchorPoint 0.5, offset position)
-- clampFn = (x, y) -> x, y   keeps it on screen
-- onClick = called if released without dragging (simple tap)
-- conn    = optional custom connect function (so temporary GUIs can clean up)
----------------------------------------------------------------------
local function makeDraggable(handle, target, clampFn, onClick, conn)
    conn = conn or connect
    local dragging, moved = false, false
    local startInput, dragStart, startPos

    conn(handle.InputBegan, function(input)
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

    conn(UIS.InputChanged, function(input)
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

local function hasDesc(opts)
    return type(opts.Description) == "string" and opts.Description ~= ""
end

local function heightFor(opts)
    return rowH() + (hasDesc(opts) and 12 or 0)
end

-- base row: rounded card with a soft outline
local function rowFrame(ctx, h, clickable)
    local row = new(clickable and "TextButton" or "Frame", {
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    if clickable then
        row.AutoButtonColor = false
        row.Text = ""
    end
    corner(row, 8)
    local st = stroke(row, Theme.Outline, 1)
    st.Transparency = 0.55
    return row, st
end

-- title (+ optional description) on the left side of a row
local function titleDesc(row, opts, name, rightW, h)
    local desc = hasDesc(opts)
    local t = label({
        Position = UDim2.new(0, 12, 0, desc and 6 or 0),
        Size = UDim2.new(1, -(12 + rightW), 0, desc and 16 or h),
        Text = name,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })
    if desc then
        label({
            Position = UDim2.new(0, 12, 0, 22),
            Size = UDim2.new(1, -(12 + rightW), 0, 14),
            Text = opts.Description,
            TextSize = 11,
            TextColor3 = Theme.SubText,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = row,
        })
    end
    return t
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
    bindRoot(obj, lbl)
    return obj
end

function Elements.Paragraph(ctx, opts)
    if type(opts) == "string" then opts = { Content = opts } end
    opts = opts or {}
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 8)
    stroke(row, Theme.Outline, 1).Transparency = 0.55
    padding(row, 12, 10, 12, 10)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
    local titleLbl = label({
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 16),
        Font = Enum.Font.GothamBold,
        Text = opts.Title or "",
        Visible = (opts.Title or "") ~= "",
        Parent = row,
    })
    local body = label({
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextSize = 12,
        TextColor3 = Theme.SubText,
        Text = opts.Content or opts.Text or "",
        Parent = row,
    })
    local obj = {}
    function obj:SetTitle(t) titleLbl.Text = t; titleLbl.Visible = t ~= "" end
    function obj:SetContent(t) body.Text = t end
    obj.SetText = obj.SetContent
    bindRoot(obj, row)
    return obj
end

function Elements.Divider(ctx, opts)
    if type(opts) == "string" then opts = { Text = opts } end
    opts = opts or {}
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Outline,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        Parent = holder,
    })
    if opts.Text and opts.Text ~= "" then
        line.Visible = false
        local l = label({
            Size = UDim2.fromScale(1, 1),
            Text = string.upper(opts.Text),
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = holder,
        })
    end
    local obj = {}
    bindRoot(obj, holder)
    return obj
end

function Elements.Button(ctx, opts)
    if type(opts) == "string" then opts = { Name = opts } end
    opts = opts or {}
    local h = heightFor(opts)
    local btn, st = rowFrame(ctx, h, true)

    local title = titleDesc(btn, opts, opts.Name or "Button", 36, h)

    local iconName = resolveIcon(opts.Icon or "mousepointerclick")
    local ico
    if iconName then
        ico = new("ImageLabel", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            Image = iconName,
            ImageColor3 = Theme.SubText,
            Parent = btn,
        })
    end

    connect(btn.MouseEnter, function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Hover })
        tween(st, 0.12, { Color = Theme.Accent, Transparency = 0.2 })
        if ico then tween(ico, 0.12, { ImageColor3 = Theme.Accent }) end
    end)
    connect(btn.MouseLeave, function()
        tween(btn, 0.12, { BackgroundColor3 = Theme.Element })
        tween(st, 0.12, { Color = Theme.Outline, Transparency = 0.55 })
        if ico then tween(ico, 0.12, { ImageColor3 = Theme.SubText }) end
    end)

    connect(btn.MouseButton1Click, function()
        btn.BackgroundColor3 = Theme.Accent
        task.delay(0.08, function()
            if btn.Parent then tween(btn, 0.3, { BackgroundColor3 = Theme.Element }) end
        end)
        fire(opts.Callback)
    end)

    local obj = {}
    function obj:SetText(t) title.Text = t end
    bindRoot(obj, btn)
    return obj
end

function Elements.Toggle(ctx, opts)
    opts = opts or {}
    local value = opts.Default and true or false
    local h = heightFor(opts)

    local row, st = rowFrame(ctx, h, true)
    hover(row, Theme.Element, Theme.Hover)

    local title = titleDesc(row, opts, opts.Name or "Toggle", 62, h)

    local track = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(38, 20),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(track, 10)
    local knob = new("Frame", {
        Position = UDim2.new(0, 3, 0.5, -7),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(knob, 7)

    local obj = { Value = value }

    local function render(animate)
        local t = animate and 0.16 or 0
        tween(track, t, { BackgroundColor3 = obj.Value and Theme.Accent or Theme.Outline })
        tween(knob, t, {
            Position = obj.Value and UDim2.new(0, 21, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        }, Enum.EasingStyle.Back)
        tween(st, t, {
            Color = obj.Value and Theme.Accent or Theme.Outline,
            Transparency = obj.Value and 0.55 or 0.55,
        })
    end

    function obj:Set(v, silent)
        v = v and true or false
        if v == self.Value then return end
        self.Value = v
        render(true)
        if not silent then fire(opts.Callback, v) end
    end
    function obj:Get() return self.Value end
    function obj:SetText(t) title.Text = t end

    connect(row.MouseButton1Click, function()
        if obj._dead then return end
        obj:Set(not obj.Value)
    end)
    onAccent(function() if not obj._dead then render(false) end end)
    render(false)
    bindFlag(obj, row, opts, "Toggle")
    return obj
end

function Elements.Slider(ctx, opts)
    opts = opts or {}
    local min, max = opts.Min or 0, opts.Max or 100
    local inc = opts.Increment or 1
    local suffix = opts.Suffix or ""
    local obj = { Value = math.clamp(opts.Default or min, min, max) }

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, MOBILE and 60 or 52),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 8)
    stroke(row, Theme.Outline, 1).Transparency = 0.55

    label({
        Position = UDim2.new(0, 12, 0, 7),
        Size = UDim2.new(1, -110, 0, 16),
        Text = opts.Name or "Slider",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })
    local valLbl = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 7),
        Size = UDim2.fromOffset(96, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextColor3 = Theme.Accent,
        Font = Enum.Font.GothamBold,
        Parent = row,
    })
    accentize(valLbl, "TextColor3")

    local bar = new("Frame", {
        Position = UDim2.new(0, 12, 1, MOBILE and -20 or -17),
        Size = UDim2.new(1, -24, 0, MOBILE and 8 or 6),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(bar, 4)
    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = bar,
    })
    corner(fill, 4)
    accentGradient(fill, 0)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(1, 0.5),
        Size = UDim2.fromOffset(MOBILE and 18 or 13, MOBILE and 18 or 13),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = fill,
    })
    corner(knob, 9)
    local knobStroke = stroke(knob, Theme.Accent, 2)
    accentize(knobStroke, "Color")

    -- larger touch area (helps on mobile)
    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 0, 24),
        Size = UDim2.new(1, 0, 1, -24),
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

    function obj:Set(v, silent) setValue(tonumber(v) or min, silent) end
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
        tween(knob, 0.1, { Size = UDim2.fromOffset(MOBILE and 22 or 17, MOBILE and 22 or 17) })
        fromX(input.Position.X)

        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                c:Disconnect()
                dragging = false
                if ctx.scroller then ctx.scroller.ScrollingEnabled = true end
                tween(knob, 0.1, { Size = UDim2.fromOffset(MOBILE and 18 or 13, MOBILE and 18 or 13) })
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
    bindFlag(obj, row, opts, "Slider")
    return obj
end

function Elements.Dropdown(ctx, opts)
    opts = opts or {}
    local options = opts.Options or {}
    local name = opts.Name or "Dropdown"
    local multi = opts.Multi and true or false
    local obj = { Value = nil, Options = options }
    local selected = {} -- multi: set of selected options
    local open = false
    local itemH = MOBILE and 38 or 28
    local query = ""

    local function fill(v)
        selected = {}
        if multi then
            if type(v) == "table" then
                for _, o in ipairs(v) do selected[o] = true end
            elseif v ~= nil then
                selected[v] = true
            end
        else
            obj.Value = v
        end
    end
    fill(opts.Default)

    local wrap = new("Frame", {
        Size = UDim2.new(1, 0, 0, rowH()),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wrap })

    local head = new("TextButton", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, rowH()),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = "",
        Parent = wrap,
    })
    corner(head, 8)
    local headStroke = stroke(head, Theme.Outline, 1)
    headStroke.Transparency = 0.55
    hover(head, Theme.Element, Theme.Hover)

    local headLbl = label({
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -44, 1, 0),
        Text = "",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = head,
    })
    local arrow = new("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Image = resolveIcon("chevrondown") or "",
        ImageColor3 = Theme.SubText,
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
    corner(list, 8)
    stroke(list, Theme.Outline, 1)
    padding(list, 5, 5, 5, 5)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

    local searchBox
    if opts.Search or #options > 8 then
        searchBox = new("TextBox", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, MOBILE and 34 or 26),
            BackgroundColor3 = Theme.Element,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search...",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = list,
        })
        corner(searchBox, 6)
        padding(searchBox, 8, 0, 8, 0)
    end

    local scroll = new("ScrollingFrame", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Parent = list,
    })
    new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

    local buttons = {}

    local function isSelected(opt)
        if multi then return selected[opt] == true end
        return opt == obj.Value
    end

    local function selectedList()
        local out = {}
        for _, o in ipairs(obj.Options) do
            if selected[o] then out[#out + 1] = o end
        end
        return out
    end

    local function updateHead()
        local text
        if multi then
            local l = selectedList()
            local parts = {}
            for _, o in ipairs(l) do parts[#parts + 1] = tostring(o) end
            text = #parts > 0 and table.concat(parts, ", ") or "-"
        else
            text = obj.Value ~= nil and tostring(obj.Value) or "-"
        end
        headLbl.Text = name .. ": " .. text
        for opt, b in pairs(buttons) do
            local on = isSelected(opt)
            b.TextColor3 = on and Theme.Accent or Theme.Text
            b.BackgroundColor3 = on and Theme.Element or Theme.Background
        end
    end

    local function relayout()
        local count = 0
        for _, b in pairs(buttons) do
            if b.Visible then count = count + 1 end
        end
        scroll.Size = UDim2.new(1, 0, 0, math.min(count * (itemH + 2), 170))
    end

    local function setOpen(state)
        open = state
        list.Visible = state
        tween(arrow, 0.15, { Rotation = state and 180 or 0 })
        tween(headStroke, 0.15, {
            Color = state and Theme.Accent or Theme.Outline,
            Transparency = state and 0.2 or 0.55,
        })
        if state then relayout() end
    end

    local function commit(silent)
        updateHead()
        if silent then return end
        if multi then fire(opts.Callback, selectedList()) else fire(opts.Callback, obj.Value) end
    end

    local function build()
        for _, b in pairs(buttons) do b:Destroy() end
        buttons = {}
        for i, opt in ipairs(obj.Options) do
            local b = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, itemH),
                BackgroundColor3 = Theme.Background,
                AutoButtonColor = false,
                Text = tostring(opt),
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                Parent = scroll,
            })
            corner(b, 6)
            b.MouseEnter:Connect(function()
                if not isSelected(opt) then tween(b, 0.1, { BackgroundColor3 = Theme.Element }) end
            end)
            b.MouseLeave:Connect(function()
                if not isSelected(opt) then tween(b, 0.1, { BackgroundColor3 = Theme.Background }) end
            end)
            connect(b.MouseButton1Click, function()
                if multi then
                    selected[opt] = (not selected[opt]) or nil
                    commit(false)
                else
                    obj.Value = opt
                    commit(false)
                    setOpen(false)
                end
            end)
            buttons[opt] = b
        end
        updateHead()
        relayout()
    end

    if searchBox then
        connect(searchBox:GetPropertyChangedSignal("Text"), function()
            query = string.lower(searchBox.Text)
            for opt, b in pairs(buttons) do
                b.Visible = query == "" or string.find(string.lower(tostring(opt)), query, 1, true) ~= nil
            end
            relayout()
        end)
    end

    function obj:Set(v, silent)
        if multi then
            fill(v)
        else
            obj.Value = v
        end
        commit(silent)
    end
    function obj:Get()
        if multi then return selectedList() end
        return self.Value
    end
    function obj:Refresh(newOptions, keepValue)
        self.Options = newOptions or {}
        if not keepValue then
            if multi then selected = {} else self.Value = nil end
        end
        build()
    end

    connect(head.MouseButton1Click, function() setOpen(not open) end)
    onAccent(function() if not obj._dead then updateHead() end end)
    build()
    bindFlag(obj, wrap, opts, "Dropdown")
    return obj
end

function Elements.Textbox(ctx, opts)
    opts = opts or {}
    local tall = MOBILE
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, tall and 70 or rowH()),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 8)
    stroke(row, Theme.Outline, 1).Transparency = 0.55

    label({
        Position = UDim2.new(0, 12, 0, tall and 6 or 0),
        Size = tall and UDim2.new(1, -20, 0, 18) or UDim2.new(1, -160, 1, 0),
        Text = opts.Name or "Textbox",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    local boxHolder = new("Frame", {
        AnchorPoint = tall and Vector2.new(0, 1) or Vector2.new(1, 0.5),
        Position = tall and UDim2.new(0, 8, 1, -8) or UDim2.new(1, -8, 0.5, 0),
        Size = tall and UDim2.new(1, -16, 0, 32) or UDim2.fromOffset(140, 24),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = row,
    })
    corner(boxHolder, 6)
    local boxStroke = stroke(boxHolder, Theme.Outline, 1)

    local box = new("TextBox", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "...",
        PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = opts.ClearOnFocus and true or false,
        Font = Enum.Font.Gotham,
        TextSize = MOBILE and 14 or 12,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClipsDescendants = true,
        Parent = boxHolder,
    })
    padding(box, 8, 0, 8, 0)

    local obj = {}

    connect(box.Focused, function()
        tween(boxStroke, 0.12, { Color = Theme.Accent })
    end)
    connect(box.FocusLost, function(enter)
        tween(boxStroke, 0.12, { Color = Theme.Outline })
        if obj._dead then return end
        fire(opts.Callback, box.Text, enter)
    end)
    if opts.Numeric then
        connect(box:GetPropertyChangedSignal("Text"), function()
            local cleaned = box.Text:gsub("[^%d%.%-]", "")
            if cleaned ~= box.Text then box.Text = cleaned end
        end)
    end

    function obj:Set(t, silent)
        box.Text = tostring(t or "")
        if silent == false then fire(opts.Callback, box.Text, false) end
    end
    function obj:Get() return box.Text end
    bindFlag(obj, row, opts, "Textbox")
    return obj
end

function Elements.Keybind(ctx, opts)
    opts = opts or {}
    local obj = { Value = opts.Default }
    local listening = false

    if type(obj.Value) == "string" then
        local okEnum, enum = pcall(function() return Enum.KeyCode[obj.Value] end)
        obj.Value = okEnum and enum or nil
    end

    local h = heightFor(opts)
    local row = rowFrame(ctx, h, false)

    titleDesc(row, opts, opts.Name or "Keybind", 120, h)

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(MOBILE and 104 or 92, MOBILE and 30 or 24),
        BackgroundColor3 = Theme.Background,
        AutoButtonColor = false,
        Text = "",
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = Theme.Text,
        Parent = row,
    })
    corner(btn, 6)
    local btnStroke = stroke(btn, Theme.Outline, 1)

    local function render()
        btn.Text = obj.Value and obj.Value.Name or "None"
        btn.TextColor3 = Theme.Text
        btnStroke.Color = Theme.Outline
    end

    function obj:Set(key, silent)
        if self._dead then return end
        if type(key) == "string" then
            if key == "" then
                key = nil
            else
                local okEnum, enum = pcall(function() return Enum.KeyCode[key] end)
                key = (okEnum and enum) or nil
            end
        end
        self.Value = key
        render()
        if silent == false then fire(opts.Changed, self.Value) end
    end
    function obj:Get() return self.Value end

    connect(btn.MouseButton1Click, function()
        if obj._dead or listening then return end
        listening = true
        Library.Listening = true
        btn.Text = "..."
        btn.TextColor3 = Theme.Accent
        btnStroke.Color = Theme.Accent
    end)

    connect(UIS.InputBegan, function(input)
        if obj._dead then return end
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
    bindFlag(obj, row, opts, "Keybind")
    return obj
end

local HUE_STOPS = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0.00, 1, 1)),
    ColorSequenceKeypoint.new(0.17, Color3.fromHSV(0.17, 1, 1)),
    ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
    ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
    ColorSequenceKeypoint.new(0.67, Color3.fromHSV(0.67, 1, 1)),
    ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
    ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1.00, 1, 1)),
})

function Elements.ColorPicker(ctx, opts)
    opts = opts or {}
    local startColor = opts.Default
    if typeof(startColor) ~= "Color3" then startColor = Theme.Accent end
    local obj = { Value = startColor }
    local h, s, v = startColor:ToHSV()
    local open = false

    local wrap = new("Frame", {
        Size = UDim2.new(1, 0, 0, rowH()),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = wrap })

    local head = new("TextButton", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, rowH()),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = "",
        Parent = wrap,
    })
    corner(head, 8)
    stroke(head, Theme.Outline, 1).Transparency = 0.55
    hover(head, Theme.Element, Theme.Hover)

    label({
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -70, 1, 0),
        Text = opts.Name or "Color",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = head,
    })
    local swatch = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(34, 18),
        BackgroundColor3 = startColor,
        BorderSizePixel = 0,
        Parent = head,
    })
    corner(swatch, 5)
    stroke(swatch, Theme.Outline, 1)

    local panel = new("Frame", {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 166),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Visible = false,
        Parent = wrap,
    })
    corner(panel, 8)
    stroke(panel, Theme.Outline, 1)

    local sv = new("Frame", {
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -44, 0, 112),
        BackgroundColor3 = Color3.fromHSV(h, 1, 1),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = panel,
    })
    corner(sv, 6)
    local white = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = sv,
    })
    new("UIGradient", {
        Transparency = NumberSequence.new(0, 1),
        Parent = white,
    })
    local black = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Parent = sv,
    })
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = black,
    })
    local svCursor = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(10, 10),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = sv,
    })
    corner(svCursor, 5)
    stroke(svCursor, Color3.new(1, 1, 1), 2)

    local hueBar = new("Frame", {
        Position = UDim2.new(1, -28, 0, 8),
        Size = UDim2.fromOffset(20, 112),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = panel,
    })
    corner(hueBar, 6)
    new("UIGradient", { Rotation = 90, Color = HUE_STOPS, Parent = hueBar })
    local hueCursor = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = hueBar,
    })
    corner(hueCursor, 2)
    stroke(hueCursor, Color3.new(0, 0, 0), 1)

    local hexBox = new("TextBox", {
        Position = UDim2.new(0, 8, 0, 130),
        Size = UDim2.new(1, -16, 0, 26),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = "#RRGGBB",
        PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = Theme.Text,
        Parent = panel,
    })
    corner(hexBox, 6)

    local function refresh(silent, fromHex)
        local c = Color3.fromHSV(h, s, v)
        obj.Value = c
        swatch.BackgroundColor3 = c
        sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
        svCursor.Position = UDim2.fromScale(s, 1 - v)
        hueCursor.Position = UDim2.fromScale(0.5, h)
        if not fromHex then hexBox.Text = "#" .. c:ToHex():upper() end
        if not silent then fire(opts.Callback, c) end
    end

    function obj:Set(c, silent)
        if type(c) == "string" then
            local okHex, parsed = pcall(Color3.fromHex, c)
            c = okHex and parsed or nil
        elseif type(c) == "table" then
            c = Color3.fromRGB(c[1] or c.r or 255, c[2] or c.g or 255, c[3] or c.b or 255)
        end
        if typeof(c) ~= "Color3" then return end
        h, s, v = c:ToHSV()
        refresh(silent)
    end
    function obj:Get() return self.Value end

    local dragMode -- "sv" | "hue"
    local function update(pos)
        if dragMode == "sv" then
            s = math.clamp((pos.X - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
            v = 1 - math.clamp((pos.Y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
        elseif dragMode == "hue" then
            h = math.clamp((pos.Y - hueBar.AbsolutePosition.Y) / math.max(hueBar.AbsoluteSize.Y, 1), 0, 1)
        end
        refresh(false)
    end
    local function beginDrag(frame, mode)
        connect(frame.InputBegan, function(input)
            if not isPress(input) then return end
            dragMode = mode
            if ctx.scroller then ctx.scroller.ScrollingEnabled = false end
            update(input.Position)
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    c:Disconnect()
                    dragMode = nil
                    if ctx.scroller then ctx.scroller.ScrollingEnabled = true end
                end
            end)
        end)
    end
    beginDrag(sv, "sv")
    beginDrag(hueBar, "hue")
    connect(UIS.InputChanged, function(input)
        if dragMode and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            update(input.Position)
        end
    end)

    connect(hexBox.FocusLost, function()
        local txt = hexBox.Text:gsub("#", "")
        local okHex, parsed = pcall(Color3.fromHex, txt)
        if okHex and typeof(parsed) == "Color3" then
            h, s, v = parsed:ToHSV()
            refresh(false)
        else
            hexBox.Text = "#" .. obj.Value:ToHex():upper()
        end
    end)

    connect(head.MouseButton1Click, function()
        open = not open
        panel.Visible = open
    end)

    refresh(true)
    bindFlag(obj, wrap, opts, "ColorPicker")
    return obj
end

local function attach(obj, ctx)
    function obj:AddLabel(o) return Elements.Label(ctx, o) end
    function obj:AddParagraph(o) return Elements.Paragraph(ctx, o) end
    function obj:AddDivider(o) return Elements.Divider(ctx, o) end
    function obj:AddButton(o) return Elements.Button(ctx, o) end
    function obj:AddToggle(o) return Elements.Toggle(ctx, o) end
    function obj:AddSlider(o) return Elements.Slider(ctx, o) end
    function obj:AddDropdown(o) return Elements.Dropdown(ctx, o) end
    function obj:AddTextbox(o) return Elements.Textbox(ctx, o) end
    function obj:AddKeybind(o) return Elements.Keybind(ctx, o) end
    function obj:AddColorPicker(o) return Elements.ColorPicker(ctx, o) end
end

----------------------------------------------------------------------
-- KEY SYSTEM
----------------------------------------------------------------------
local function httpRequest(o)
    local fn = (type(request) == "function" and request)
        or (type(http_request) == "function" and http_request)
        or (syn and type(syn.request) == "function" and syn.request)
        or (http and type(http.request) == "function" and http.request)
        or (fluxus and type(fluxus.request) == "function" and fluxus.request)
    if not fn then return nil, "Your executor has no request function." end
    local ok, res = pcall(fn, o)
    if not ok then return nil, tostring(res) end
    if type(res) ~= "table" then return nil, "Empty response." end
    return res
end

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end
    local res = httpRequest({ Url = url, Method = "GET" })
    if res and type(res.Body) == "string" then return res.Body end
    return nil
end

local function jsonDecode(s)
    local ok, data = pcall(function() return HttpService:JSONDecode(s) end)
    if ok then return data end
    return nil
end

local function getHwid()
    local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
    if ok and id then return tostring(id) end
    return tostring(LocalPlayer.UserId)
end
Library.GetHwid = getHwid

local function sha256(s)
    local attempts = {
        function() return crypt.hash(s, "sha256") end,
        function() return syn.crypt.custom.hash("sha256", s) end,
        function() return crypt.custom.hash("sha256", s) end,
        function() return sha256_hash(s) end,
    }
    for _, f in ipairs(attempts) do
        local ok, r = pcall(f)
        if ok and type(r) == "string" and #r > 0 then return string.lower(r) end
    end
    return nil
end

local function copyText(text)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(fn) == "function" then
        local ok = pcall(fn, text)
        return ok
    end
    return false
end
Library.CopyText = copyText

-- Provider contract:
--   Validate(cfg, key, hwid) -> valid:boolean, message:string?, info:any?
--   GetLink(cfg)             -> url:string?, err:string?      (optional)
function Library:RegisterKeyProvider(name, provider)
    if type(name) ~= "string" or type(provider) ~= "table" or type(provider.Validate) ~= "function" then
        error("[AzureUI] RegisterKeyProvider(name, {Validate = function(cfg, key, hwid) ... end})")
    end
    self.KeyProviders[string.lower(name)] = provider
end

-- Static list of keys ---------------------------------------------------
Library:RegisterKeyProvider("static", {
    Validate = function(cfg, key)
        for _, k in ipairs(cfg.Keys or {}) do
            if tostring(k) == key then return true, "Key accepted." end
        end
        return false, "Invalid key."
    end,
})

-- Your own function -----------------------------------------------------
Library:RegisterKeyProvider("custom", {
    Validate = function(cfg, key, hwid)
        if type(cfg.Validate) ~= "function" then return false, "No Validate function set." end
        local ok, msg, info = cfg.Validate(key, hwid)
        if ok then return true, type(msg) == "string" and msg or "Key accepted.", info end
        return false, type(msg) == "string" and msg or "Invalid key."
    end,
})

-- Luarmor ----------------------------------------------------------------
local LUARMOR_MESSAGES = {
    KEY_VALID = "Key valid!",
    KEY_INCORRECT = "Wrong key.",
    KEY_INVALID = "Invalid key format.",
    KEY_HWID_LOCKED = "This key is linked to another device. Reset your HWID first.",
    KEY_EXPIRED = "This key has expired.",
    KEY_BANNED = "This key is banned.",
    KEY_BLACKLISTED = "This key is blacklisted.",
    SCRIPT_ID_INCORRECT = "Wrong script id in the loader.",
    SCRIPT_ID_INVALID = "Invalid script id in the loader.",
    INVALID_EXECUTOR = "This executor is not supported.",
    SECURE_MODE_ENABLED = "Secure mode is on - use the official loader.",
    ERROR = "Luarmor returned an error.",
}

Library:RegisterKeyProvider("luarmor", {
    Validate = function(cfg, key)
        if not cfg.ScriptId then return false, "ScriptId is missing in the key config." end
        if not cfg._luarmorApi then
            local src = httpGet(cfg.LuarmorLibrary or "https://sdkapi-public.luarmor.net/library.lua")
            local fn = src and loadstring and loadstring(src)
            local okApi, api = false, nil
            if fn then okApi, api = pcall(fn) end
            if not okApi or type(api) ~= "table" then
                return false, "Could not reach Luarmor."
            end
            cfg._luarmorApi = api
        end
        local api = cfg._luarmorApi
        api.script_id = tostring(cfg.ScriptId)
        local ok, status = pcall(api.check_key, key)
        if not ok or type(status) ~= "table" then
            return false, "Luarmor check failed."
        end
        local code = tostring(status.code or "ERROR")
        if code == "KEY_VALID" then
            env.script_key = key
            local info = {
                Api = api,
                Status = status,
                Load = function() return api.load_script() end,
            }
            if cfg.AutoLoad then pcall(api.load_script) end
            return true, LUARMOR_MESSAGES.KEY_VALID, info
        end
        return false, LUARMOR_MESSAGES[code] or tostring(status.message or code)
    end,
})

-- Platoboost -----------------------------------------------------------
-- Uses the public endpoints from Platoboost's loader template. Compare with the
-- template shown in your Platoboost dashboard if something does not match.
local function pbCall(cfg, method, path, query, body)
    local host = tostring(cfg.Host or "https://api.platoboost.net"):gsub("/+$", "")
    local url = host .. path
    if query then url = url .. "?" .. query end
    local req = { Url = url, Method = method, Headers = { ["Content-Type"] = "application/json" } }
    if body then req.Body = HttpService:JSONEncode(body) end
    local res, err = httpRequest(req)
    if not res then return nil, err end
    local data = jsonDecode(res.Body)
    if type(data) ~= "table" then
        return nil, "Bad response from Platoboost (" .. tostring(res.StatusCode) .. ")."
    end
    return data
end

Library:RegisterKeyProvider("platoboost", {
    GetLink = function(cfg)
        if not cfg.Service then return nil, "Service is missing in the key config." end
        local data, err = pbCall(cfg, "POST", "/public/start", nil, {
            service = tonumber(cfg.Service) or cfg.Service,
            identifier = cfg.Identifier or getHwid(),
        })
        if not data then return nil, err end
        if data.success and type(data.data) == "table" and data.data.url then
            return data.data.url
        end
        return nil, tostring(data.message or "Could not create the key link.")
    end,
    Validate = function(cfg, key)
        if not cfg.Service then return false, "Service is missing in the key config." end
        local hwid = cfg.Identifier or getHwid()
        local service = tostring(cfg.Service)

        local query = "identifier=" .. HttpService:UrlEncode(hwid) .. "&key=" .. HttpService:UrlEncode(key)
        local nonce
        if cfg.UseNonce then
            nonce = randomSegment(16)
            query = query .. "&nonce=" .. nonce
        end

        local data, err = pbCall(cfg, "GET", "/public/whitelist/" .. service, query)
        if not data then return false, err end
        if data.success and type(data.data) == "table" and data.data.valid then
            if cfg.UseNonce then
                local want = sha256(tostring(data.data.valid) .. "-" .. nonce .. "-" .. tostring(cfg.Secret or ""))
                if not want then return false, "This executor has no SHA-256 (needed for UseNonce)." end
                if string.lower(tostring(data.data.hash or "")) ~= want then
                    return false, "Response signature mismatch."
                end
            end
            return true, "Key valid!"
        end

        -- not whitelisted yet: try to redeem it (premium keys)
        local red = pbCall(cfg, "POST", "/public/redeem/" .. service, nil, { identifier = hwid, key = key })
        if red and red.success then return true, "Key redeemed!" end

        local msg = (red and red.message) or data.message
        return false, tostring(msg or "Invalid or expired key.")
    end,
})

-- Generic HTTP provider ---------------------------------------------------
--   Url = "https://example.com/check?key={key}&hwid={hwid}"
--   Method = "GET" | "POST", Headers = {...}, Body = '{"key":"{key}"}'
--   SuccessText = "valid"                    -- plain text found in the response, OR
--   SuccessField = "data.valid", SuccessValue = true
--   MessageField = "message"                 -- optional
Library:RegisterKeyProvider("http", {
    Validate = function(cfg, key, hwid)
        if not cfg.Url then return false, "Url is missing in the key config." end
        local map = {
            key = key, hwid = hwid, service = tostring(cfg.Service or ""),
            userid = tostring(LocalPlayer.UserId), username = LocalPlayer.Name,
        }
        local function fill(s, encode)
            return (tostring(s):gsub("{(%w+)}", function(k)
                local v = map[k]
                if v == nil then return nil end
                return encode and HttpService:UrlEncode(v) or v
            end))
        end
        local req = {
            Url = fill(cfg.Url, true),
            Method = cfg.Method or "GET",
            Headers = cfg.Headers,
        }
        if cfg.Body then req.Body = fill(cfg.Body, false) end
        local res, err = httpRequest(req)
        if not res then return false, err end
        local body = tostring(res.Body or "")

        local decoded = jsonDecode(body)
        local function field(path)
            local cur = decoded
            for part in tostring(path):gmatch("[^%.]+") do
                if type(cur) ~= "table" then return nil end
                cur = cur[part]
            end
            return cur
        end

        local ok
        if cfg.SuccessText then
            ok = string.find(body, tostring(cfg.SuccessText), 1, true) ~= nil
        elseif cfg.SuccessField then
            local want = cfg.SuccessValue
            if want == nil then want = true end
            ok = tostring(field(cfg.SuccessField)) == tostring(want)
        else
            ok = res.StatusCode == 200
        end

        local msg
        if cfg.MessageField then msg = field(cfg.MessageField) end
        if ok then return true, type(msg) == "string" and msg or "Key valid!", decoded end
        return false, type(msg) == "string" and msg or "Invalid key."
    end,
})

-- Key window ----------------------------------------------------------------
function Library:KeySystem(opts)
    opts = opts or {}
    if opts.Callback == nil and opts.OnSuccess then opts.Callback = opts.OnSuccess end

    local title = opts.Title or "Key System"
    local subtitle = opts.Subtitle or "Enter your key to continue"
    local iconId = toAsset(opts.Icon or DEFAULT_ICON)

    local pname = string.lower(tostring(
        opts.Provider or (opts.Keys and "static") or (opts.Validate and "custom") or "static"))
    local prov = Library.KeyProviders[pname]
    if not prov then
        error("[AzureUI] unknown key provider '" .. pname .. "'. Use RegisterKeyProvider first.")
    end

    local hwid = opts.Identifier or getHwid()
    local keyId = cleanConfigName(pname .. "_" .. tostring(opts.ScriptId or opts.Service or opts.Id or title), "key")
    local keyPath = CONFIG_FOLDER .. "/keys/" .. keyId .. ".txt"
    local saveKey = opts.SaveKey ~= false

    local function readSaved()
        if not saveKey then return nil end
        if hasFS() then
            local ok, data = pcall(readfile, keyPath)
            if ok and type(data) == "string" then
                data = data:gsub("%s+", "")
                if data ~= "" then return data end
            end
        end
        local mem = type(env.AzureUI_Keys) == "table" and env.AzureUI_Keys[keyId]
        if type(mem) == "string" and mem ~= "" then return mem end
        return nil
    end
    local function writeSaved(key)
        if not saveKey then return end
        env.AzureUI_Keys = env.AzureUI_Keys or {}
        env.AzureUI_Keys[keyId] = key
        if hasFS() then
            ensureFolder("keys")
            pcall(writefile, keyPath, key)
        end
    end
    local function clearSaved()
        if env.AzureUI_Keys then env.AzureUI_Keys[keyId] = nil end
        if hasFS() then pcall(writefile, keyPath, "") end
    end

    local done, resultOk, resultKey, resultInfo = false, false, nil, nil
    local kconns = {}
    local function kconnect(signal, fn)
        local c = signal:Connect(fn)
        kconns[#kconns + 1] = c
        return c
    end

    -- GUI ---------------------------------------------------------------
    local gui = new("ScreenGui", {
        Name = randomGuiName(),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 1000,
    })
    protectGui(gui)
    gui.Parent = getGuiParent()
    if env.AzureUI_KeyGui and env.AzureUI_KeyGui.Parent then pcall(function() env.AzureUI_KeyGui:Destroy() end) end
    env.AzureUI_KeyGui = gui

    local dim = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Parent = gui,
    })
    tween(dim, 0.3, { BackgroundTransparency = 0.45 })

    local vp = screenSize()
    local cardW = math.clamp(vp.X - 24, 280, MOBILE and 360 or 400)

    local root = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2)),
        Size = UDim2.fromOffset(cardW, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local scale = new("UIScale", { Scale = 0.9, Parent = root })
    dropShadow(root, 30, 0.45)

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = root,
    })
    corner(card, 14)
    stroke(card, Theme.Outline, 1)
    new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Theme.Section, Theme.Background),
        Parent = card,
    })

    local topLine = new("Frame", {
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = card,
    })
    accentGradient(topLine, 0)

    local content = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = card,
    })
    padding(content, 22, 22, 22, 22)
    new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })

    -- header (drag handle)
    local header = new("Frame", {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        Parent = content,
    })
    local logoBg = new("Frame", {
        Size = UDim2.fromOffset(44, 44),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(logoBg, 12)
    stroke(logoBg, Theme.Accent, 1).Transparency = 0.4
    new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        Image = iconId,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoBg,
    })
    label({
        Position = UDim2.fromOffset(56, 3),
        Size = UDim2.new(1, -96, 0, 20),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        Text = title,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = header,
    })
    label({
        Position = UDim2.fromOffset(56, 24),
        Size = UDim2.new(1, -96, 0, 16),
        TextSize = 12,
        TextColor3 = Theme.SubText,
        Text = subtitle,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = header,
    })
    local closeBtn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = Theme.Element,
        AutoButtonColor = false,
        Text = "×",
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        TextColor3 = Theme.SubText,
        Parent = header,
    })
    corner(closeBtn, 8)
    kconnect(closeBtn.MouseEnter, function()
        tween(closeBtn, 0.12, { BackgroundColor3 = Theme.Danger, TextColor3 = Color3.new(1, 1, 1) })
    end)
    kconnect(closeBtn.MouseLeave, function()
        tween(closeBtn, 0.12, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.SubText })
    end)

    if opts.Note and opts.Note ~= "" then
        label({
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = opts.Note,
            Parent = content,
        })
    end

    -- key input
    local inputWrap = new("Frame", {
        LayoutOrder = 3,
        Size = UDim2.new(1, 0, 0, MOBILE and 46 or 42),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Parent = content,
    })
    corner(inputWrap, 10)
    local inputStroke = stroke(inputWrap, Theme.Outline, 1)
    new("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Image = resolveIcon("key") or "",
        ImageColor3 = Theme.SubText,
        Parent = inputWrap,
    })
    local keyBox = new("TextBox", {
        Position = UDim2.fromOffset(38, 0),
        Size = UDim2.new(1, -48, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.Placeholder or "Paste your key here",
        PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = false,
        Font = Enum.Font.Code,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClipsDescendants = true,
        Parent = inputWrap,
    })
    kconnect(keyBox.Focused, function() tween(inputStroke, 0.12, { Color = Theme.Accent }) end)
    kconnect(keyBox.FocusLost, function() tween(inputStroke, 0.12, { Color = Theme.Outline }) end)

    -- status
    local statusLbl = label({
        LayoutOrder = 4,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextSize = 12,
        TextColor3 = Theme.SubText,
        Text = "",
        Visible = false,
        Parent = content,
    })
    local STATUS_COLORS = {
        info = Theme.SubText, ok = Theme.Success, err = Theme.Danger, warn = Theme.Warning,
    }
    local function setStatus(text, kind)
        statusLbl.Text = text or ""
        statusLbl.Visible = text ~= nil and text ~= ""
        statusLbl.TextColor3 = STATUS_COLORS[kind or "info"] or Theme.SubText
    end

    -- buttons
    local function makeButton(parent, text, primary)
        local b = new("TextButton", {
            BackgroundColor3 = primary and Color3.new(1, 1, 1) or Theme.Element,
            AutoButtonColor = false,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = primary and Color3.new(1, 1, 1) or Theme.Text,
            Parent = parent,
        })
        corner(b, 10)
        if primary then
            accentGradient(b, 0)
            b.BackgroundColor3 = Color3.new(1, 1, 1)
        else
            stroke(b, Theme.Outline, 1).Transparency = 0.4
            kconnect(b.MouseEnter, function() tween(b, 0.12, { BackgroundColor3 = Theme.Hover }) end)
            kconnect(b.MouseLeave, function() tween(b, 0.12, { BackgroundColor3 = Theme.Element }) end)
        end
        return b
    end

    local btnRow = new("Frame", {
        LayoutOrder = 5,
        Size = UDim2.new(1, 0, 0, MOBILE and 44 or 40),
        BackgroundTransparency = 1,
        Parent = content,
    })
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = btnRow,
    })

    local hasLink = opts.GetKeyLink ~= nil or prov.GetLink ~= nil
    local count = hasLink and 2 or 1
    local function slot() return UDim2.new(1 / count, -(8 * (count - 1)) / count, 1, 0) end

    local verifyBtn = makeButton(btnRow, "Verify Key", true)
    verifyBtn.LayoutOrder = 1
    verifyBtn.Size = slot()

    local linkBtn
    if hasLink then
        linkBtn = makeButton(btnRow, "Get Key", false)
        linkBtn.LayoutOrder = 2
        linkBtn.Size = slot()
    end

    -- extra buttons (Discord, Website...)
    local extras = {}
    if opts.Discord then
        extras[#extras + 1] = { Name = "Discord", Link = opts.Discord }
    end
    if type(opts.Buttons) == "table" then
        for _, e in ipairs(opts.Buttons) do extras[#extras + 1] = e end
    end
    if #extras > 0 then
        local row2 = new("Frame", {
            LayoutOrder = 6,
            Size = UDim2.new(1, 0, 0, MOBILE and 40 or 34),
            BackgroundTransparency = 1,
            Parent = content,
        })
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = row2,
        })
        local n = #extras
        for i, e in ipairs(extras) do
            local b = makeButton(row2, tostring(e.Name or "Link"), false)
            b.LayoutOrder = i
            b.TextSize = 12
            b.Size = UDim2.new(1 / n, -(8 * (n - 1)) / n, 1, 0)
            kconnect(b.MouseButton1Click, function()
                if e.Callback then fire(e.Callback) end
                if e.Link then
                    if copyText(e.Link) then
                        setStatus(tostring(e.Name or "Link") .. " link copied to clipboard.", "ok")
                    else
                        setStatus(e.Link, "info")
                    end
                end
            end)
        end
    end

    -- logic -----------------------------------------------------------------
    local busy = false
    local function setBusy(state)
        busy = state
        verifyBtn.Text = state and "Checking..." or "Verify Key"
        verifyBtn.TextTransparency = state and 0.35 or 0
    end

    local function shake()
        local base = root.Position
        for i = 1, 3 do
            tween(root, 0.04, { Position = base + UDim2.fromOffset(8, 0) })
            task.wait(0.04)
            tween(root, 0.04, { Position = base - UDim2.fromOffset(8, 0) })
            task.wait(0.04)
        end
        tween(root, 0.05, { Position = base })
    end

    local function finish(ok, key, info)
        if done then return end
        done, resultOk, resultKey, resultInfo = true, ok, key, info
        for _, c in ipairs(kconns) do pcall(function() c:Disconnect() end) end
        tween(dim, 0.25, { BackgroundTransparency = 1 })
        local t = tween(scale, 0.22, { Scale = 0.9 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
        tween(card, 0.2, { BackgroundTransparency = 1 })
        task.delay(0.25, function()
            pcall(function() gui:Destroy() end)
            if env.AzureUI_KeyGui == gui then env.AzureUI_KeyGui = nil end
        end)
        if ok then
            fire(opts.Callback, key, info)
        else
            fire(opts.OnClose)
        end
    end

    local function verify(key, silent)
        key = tostring(key or ""):gsub("%s+", "")
        if key == "" then
            setStatus("Enter your key first.", "warn")
            return
        end
        if busy or done then return end
        setBusy(true)
        setStatus(silent and "Checking saved key..." or "Checking key...", "info")
        task.spawn(function()
            local ok, valid, msg, info = pcall(prov.Validate, opts, key, hwid)
            setBusy(false)
            if done then return end
            if not ok then
                setStatus("Error: " .. tostring(valid), "err")
                fire(opts.OnFail, key, tostring(valid))
                return
            end
            if valid then
                setStatus(msg or "Key valid!", "ok")
                writeSaved(key)
                task.wait(0.7)
                finish(true, key, info)
            else
                if silent then
                    clearSaved()
                    setStatus("Your saved key is no longer valid. Enter a new one.", "warn")
                else
                    setStatus(msg or "Invalid key.", "err")
                    shake()
                end
                fire(opts.OnFail, key, msg)
            end
        end)
    end

    kconnect(verifyBtn.MouseButton1Click, function() verify(keyBox.Text, false) end)
    kconnect(keyBox.FocusLost, function(enter)
        if enter then verify(keyBox.Text, false) end
    end)
    kconnect(closeBtn.MouseButton1Click, function() finish(false) end)

    if linkBtn then
        kconnect(linkBtn.MouseButton1Click, function()
            if busy then return end
            setBusy(true)
            setStatus("Getting your key link...", "info")
            task.spawn(function()
                local link, err
                local src = opts.GetKeyLink
                if type(src) == "function" then
                    local ok, r1, r2 = pcall(src, opts, hwid)
                    if ok then link, err = r1, r2 else err = tostring(r1) end
                elseif type(src) == "string" then
                    link = src
                elseif prov.GetLink then
                    local ok, r1, r2 = pcall(prov.GetLink, opts)
                    if ok then link, err = r1, r2 else err = tostring(r1) end
                end
                setBusy(false)
                if done then return end
                if type(link) == "string" and link ~= "" then
                    if copyText(link) then
                        setStatus("Key link copied! Open it in your browser.", "ok")
                    else
                        setStatus("Open this link in your browser: " .. link, "info")
                    end
                else
                    setStatus(tostring(err or "Could not get the key link."), "err")
                end
            end)
        end)
    end

    makeDraggable(header, root, function(x, y)
        local v = screenSize()
        return math.clamp(x, 40, math.max(40, v.X - 40)), math.clamp(y, 40, math.max(40, v.Y - 40))
    end, nil, kconnect)

    tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

    -- auto login with the saved key
    local saved = readSaved()
    if saved then
        keyBox.Text = saved
        task.defer(function() verify(saved, true) end)
    end

    -- block until finished unless a Callback was given
    if opts.Callback ~= nil or opts.Async then
        return {
            Close = function() finish(false) end,
            IsDone = function() return done end,
        }
    end
    while not done do task.wait(0.1) end
    return resultOk, resultKey, resultInfo
end

-- remove the saved key of a key system (e.g. from a "logout" button)
function Library:ClearSavedKey(provider, id)
    local keyId = cleanConfigName(string.lower(tostring(provider)) .. "_" .. tostring(id), "key")
    if env.AzureUI_Keys then env.AzureUI_Keys[keyId] = nil end
    if hasFS() then pcall(writefile, CONFIG_FOLDER .. "/keys/" .. keyId .. ".txt", "") end
end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
function Library:CreateWindow(opts)
    opts = opts or {}
    if type(opts.Theme) == "table" then self:SetTheme(opts.Theme) end

    -- optional key gate: CreateWindow({ KeySystem = {...} }) returns nil if the key fails
    if opts.KeySystem then
        local ok = self:KeySystem(opts.KeySystem)
        if not ok then return nil end
    end

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
    local sideOrder = 0

    -- ScreenGui (random name every 5s) -------------------------------
    local gui = new("ScreenGui", {
        Name = randomGuiName(),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
    })
    protectGui(gui)
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
    local maxW = math.min(opts.Width or (MOBILE and 440 or 600), math.max(280, vp.X - 8))
    local maxH = math.min(opts.Height or (MOBILE and math.floor(vp.Y * 0.78) or 470), math.max(240, vp.Y - 8))
    local margin = MOBILE and 10 or 24
    local width = math.clamp(vp.X - margin * 2, MOBILE and 280 or 340, maxW)
    local height = math.clamp(vp.Y - (MOBILE and 64 or 72), 240, maxH)
    local sidebarW = width < 480 and (MOBILE and 116 or 108) or 150
    local TOPBAR = MOBILE and 50 or 44
    local showProfile = opts.Profile ~= false
    local PROFILE_H = showProfile and (MOBILE and 56 or 50) or 0

    -- root = movable/resizable holder (shadow + main), main = clipped window
    local root = new("Frame", {
        Name = "Root",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2)),
        Size = UDim2.fromOffset(width, height),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local rootScale = new("UIScale", { Scale = 1, Parent = root })
    dropShadow(root, 30, 0.5)

    local main = new("Frame", {
        Name = "Main",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Main,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 1,
        Parent = root,
    })
    corner(main, 12)
    stroke(main, Theme.Outline, 1)

    -- Top bar (drag here) ------------------------------------
    local topbar = new("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, TOPBAR),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = main,
    })
    new("UIGradient", {
        Color = ColorSequence.new(Theme.Background, Theme.Main),
        Parent = topbar,
    })
    local accentLine = new("Frame", { -- accent line
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Parent = topbar,
    })
    accentGradient(accentLine, 0)
    new("Frame", { -- divider
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        Parent = topbar,
    })

    local logoBg = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 1),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        Parent = topbar,
    })
    corner(logoBg, 8)
    local logoStroke = stroke(logoBg, Theme.Accent, 1)
    logoStroke.Transparency = 0.45
    accentize(logoStroke, "Color")
    new("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Image = iconId,
        ScaleType = Enum.ScaleType.Fit,
        Parent = logoBg,
    })

    local titleLbl = label({
        Position = UDim2.new(0, 46, 0, 2),
        Size = UDim2.new(1, MOBILE and -140 or -126, 1, -2),
        Font = Enum.Font.GothamBold,
        RichText = true,
        TextSize = 14,
        Text = "",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = topbar,
    })
    local function setTitle(t, s)
        title, subtitle = t or title, s == nil and subtitle or s
        titleLbl.Text = title .. (subtitle ~= "" and ('  <font color="#858FA4" size="11">' .. subtitle .. "</font>") or "")
    end
    setTitle(title, subtitle)
    function Window:SetTitle(t, s) setTitle(t, s) end

    local function topButton(text, xOffset, hoverColor)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, xOffset, 0.5, 1),
            Size = UDim2.fromOffset(MOBILE and 36 or 28, MOBILE and 32 or 26),
            BackgroundColor3 = Theme.Element,
            AutoButtonColor = false,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = MOBILE and 18 or 16,
            TextColor3 = Theme.SubText,
            Parent = topbar,
        })
        corner(b, 8)
        connect(b.MouseEnter, function()
            tween(b, 0.12, { BackgroundColor3 = hoverColor, TextColor3 = Color3.new(1, 1, 1) })
        end)
        connect(b.MouseLeave, function()
            tween(b, 0.12, { BackgroundColor3 = Theme.Element, TextColor3 = Theme.SubText })
        end)
        return b
    end
    local minBtn = topButton("–", MOBILE and -52 or -42, Theme.Hover)
    local closeBtn = topButton("×", -8, Theme.Danger)

    -- Sidebar + pages ------------------------------------------------
    local sidebar = new("ScrollingFrame", {
        Name = "Sidebar",
        Position = UDim2.fromOffset(0, TOPBAR),
        Size = UDim2.new(0, sidebarW, 1, -TOPBAR - PROFILE_H),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = main,
    })
    padding(sidebar, 8, 10, 8, 8)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sidebar })
    local sideBorder = new("Frame", {
        Name = "SideBorder",
        Position = UDim2.new(0, sidebarW - 1, 0, TOPBAR),
        Size = UDim2.new(0, 1, 1, -TOPBAR),
        BackgroundColor3 = Theme.Outline,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = main,
    })

    local profile
    if showProfile then
        profile = new("Frame", {
            Name = "Profile",
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(0, sidebarW, 0, PROFILE_H),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            Parent = main,
        })
        new("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Outline,
            BorderSizePixel = 0,
            Parent = profile,
        })
        local avatar = new("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(MOBILE and 34 or 30, MOBILE and 34 or 30),
            BackgroundColor3 = Theme.Element,
            BorderSizePixel = 0,
            Image = "",
            Parent = profile,
        })
        corner(avatar, 99)
        local avStroke = stroke(avatar, Theme.Accent, 1.5)
        accentize(avStroke, "Color")
        local textLeft = (MOBILE and 34 or 30) + 18
        label({
            Position = UDim2.new(0, textLeft, 0.5, -15),
            Size = UDim2.new(1, -(textLeft + 6), 0, 16),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            Text = opts.ProfileName or LocalPlayer.DisplayName,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = profile,
        })
        label({
            Position = UDim2.new(0, textLeft, 0.5, 1),
            Size = UDim2.new(1, -(textLeft + 6), 0, 14),
            TextSize = 11,
            TextColor3 = Theme.SubText,
            Text = "@" .. LocalPlayer.Name,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = profile,
        })
        task.spawn(function()
            local ok, url = pcall(function()
                return Players:GetUserThumbnailAsync(
                    LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            end)
            if ok and avatar.Parent then avatar.Image = url end
        end)
    end

    local pages = new("Frame", {
        Name = "Pages",
        Position = UDim2.fromOffset(sidebarW, TOPBAR),
        Size = UDim2.new(1, -sidebarW, 1, -TOPBAR),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = main,
    })

    -- Notifications -----------------------------------------------------
    local notifyHolder = new("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -12, 1, -12),
        Size = UDim2.new(0, 260, 1, -24),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        Parent = notifyHolder,
    })
    local notifyCount = 0

    local NOTIFY_ICONS = { info = "info", success = "checkcircle", warning = "alerttriangle", error = "xcircle" }

    function Window:Notify(o)
        o = o or {}
        notifyCount = notifyCount + 1
        local kind = string.lower(tostring(o.Type or "info"))
        if kind == "warn" then kind = "warning" elseif kind == "err" then kind = "error" end
        if not NOTIFY_ICONS[kind] then kind = "info" end
        local color = ({
            info = Theme.Accent, success = Theme.Success, warning = Theme.Warning, error = Theme.Danger,
        })[kind]
        local duration = o.Duration or 4

        local card = new("CanvasGroup", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Main,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            LayoutOrder = notifyCount,
            Parent = notifyHolder,
        })
        corner(card, 10)
        stroke(card, Theme.Outline, 1)
        new("Frame", {
            Size = UDim2.new(0, 3, 1, 0),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Parent = card,
        })
        local ico = resolveIcon(o.Icon or NOTIFY_ICONS[kind])
        if ico then
            new("ImageLabel", {
                Position = UDim2.fromOffset(14, 11),
                Size = UDim2.fromOffset(18, 18),
                BackgroundTransparency = 1,
                Image = ico,
                ImageColor3 = color,
                Parent = card,
            })
        end
        local inner = new("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Parent = card,
        })
        padding(inner, 42, 10, 12, 14)
        new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = inner })
        label({
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 18),
            Font = Enum.Font.GothamBold,
            Text = o.Title or title,
            TextTruncate = Enum.TextTruncate.AtEnd,
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

        local barBg = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = Theme.Outline,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            Parent = card,
        })
        local barFill = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
            Parent = barBg,
        })

        tween(card, 0.25, { GroupTransparency = 0 })
        tween(barFill, duration, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
        task.delay(duration, function()
            if not card.Parent then return end
            local t = tween(card, 0.3, { GroupTransparency = 1 })
            t.Completed:Connect(function() card:Destroy() end)
        end)
    end

    -- Dialog (modal inside the window) -----------------------------------------
    function Window:Dialog(o)
        o = o or {}
        local overlay = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 50,
            Parent = main,
        })
        tween(overlay, 0.15, { BackgroundTransparency = 0.5 })
        local box = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, math.min(320, math.max(220, root.Size.X.Offset - 40)), 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Element,
            BorderSizePixel = 0,
            Parent = overlay,
        })
        corner(box, 12)
        stroke(box, Theme.Outline, 1)
        padding(box, 16, 16, 16, 16)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
        label({
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 18),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            Text = o.Title or title,
            Parent = box,
        })
        label({
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = o.Content or "",
            Parent = box,
        })
        local row = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, MOBILE and 40 or 34),
            BackgroundTransparency = 1,
            Parent = box,
        })
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = row,
        })
        local buttons = o.Buttons
        if type(buttons) ~= "table" or #buttons == 0 then buttons = { { Name = "OK" } } end
        local function close()
            tween(overlay, 0.12, { BackgroundTransparency = 1 })
            task.delay(0.12, function() overlay:Destroy() end)
        end
        for i, b in ipairs(buttons) do
            local primary = (i == #buttons)
            local btn = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(0, 90, 1, 0),
                BackgroundColor3 = primary and Theme.Accent or Theme.Background,
                AutoButtonColor = false,
                Text = tostring(b.Name or "OK"),
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Text,
                Parent = row,
            })
            corner(btn, 8)
            connect(btn.MouseButton1Click, function()
                close()
                fire(b.Callback)
            end)
        end
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
    local floatStroke = stroke(float, Theme.Accent, 2)
    accentize(floatStroke, "Color")
    dropShadow(float, 12, 0.6)
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

    -- Clamp + resize ------------------------------------------------------
    local function applyChrome(w, h)
        local v = screenSize()
        local minW = MOBILE and 270 or 320
        local minH = 230
        w = math.clamp(math.floor(w + 0.5), minW, math.max(minW, v.X - 8))
        h = math.clamp(math.floor(h + 0.5), minH, math.max(minH, v.Y - 8))
        local sw = (w < 480) and (MOBILE and 116 or 108) or 150
        sidebarW = sw
        sidebar.Position = UDim2.fromOffset(0, TOPBAR)
        sidebar.Size = UDim2.new(0, sw, 1, -TOPBAR - PROFILE_H)
        sideBorder.Position = UDim2.new(0, sw - 1, 0, TOPBAR)
        sideBorder.Size = UDim2.new(0, 1, 1, -TOPBAR)
        if profile then profile.Size = UDim2.new(0, sw, 0, PROFILE_H) end
        pages.Position = UDim2.fromOffset(sw, TOPBAR)
        pages.Size = UDim2.new(1, -sw, 1, -TOPBAR)
        root.Size = UDim2.fromOffset(w, h)
        local nw = math.clamp(math.floor(v.X * (MOBILE and 0.86 or 0.28)), 200, 320)
        notifyHolder.Size = UDim2.fromOffset(nw, math.max(80, v.Y - 20))
        local lay = notifyHolder:FindFirstChildOfClass("UIListLayout")
        if MOBILE then
            notifyHolder.AnchorPoint = Vector2.new(0.5, 0)
            notifyHolder.Position = UDim2.new(0.5, 0, 0, 8)
            if lay then lay.VerticalAlignment = Enum.VerticalAlignment.Top end
        else
            notifyHolder.AnchorPoint = Vector2.new(1, 1)
            notifyHolder.Position = UDim2.new(1, -12, 1, -12)
            if lay then lay.VerticalAlignment = Enum.VerticalAlignment.Bottom end
        end
        return w, h
    end

    local function clampMain(x, y)
        local v = screenSize()
        local w = root.Size.X.Offset
        local h = root.Size.Y.Offset
        local minX = w / 2
        local maxX = math.max(minX, v.X - w / 2)
        local minY = h / 2
        local maxY = math.max(minY, v.Y - h / 2)
        return math.clamp(x, minX, maxX), math.clamp(y, minY, maxY)
    end

    function Window:SetSize(w, h)
        applyChrome(w, h)
        local x, y = clampMain(root.Position.X.Offset, root.Position.Y.Offset)
        root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end

    function Window:GetState()
        return {
            x = root.Position.X.Offset,
            y = root.Position.Y.Offset,
            w = root.Size.X.Offset,
            h = root.Size.Y.Offset,
        }
    end

    function Window:SetState(state)
        if type(state) ~= "table" then return end
        if tonumber(state.w) and tonumber(state.h) then
            applyChrome(tonumber(state.w), tonumber(state.h))
        end
        if tonumber(state.x) and tonumber(state.y) then
            local x, y = clampMain(tonumber(state.x), tonumber(state.y))
            root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
        end
    end

    function Window:SaveConfig(name)
        return Library:SaveConfig(name or "default", self:GetState())
    end

    function Window:LoadConfig(name)
        local ok, payload = Library:LoadConfig(name or "default")
        if ok and type(payload) == "table" then
            self:SetState(payload.window)
        end
        return ok
    end

    function Window:DeleteConfig(name)
        return Library:DeleteConfig(name or "default")
    end

    function Window:TryAutoLoad()
        local name = Library:GetAutoload()
        if not name or name == "" then return false end
        return self:LoadConfig(name)
    end

    Window:SetSize(width, height)

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
            local t = tween(rootScale, 0.22, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
            t.Completed:Connect(function(ps)
                if ps == Enum.PlaybackState.Completed and self.Minimized then root.Visible = false end
            end)
            if self.FloatEnabled then
                float.Visible = true
                floatScale.Scale = 0
                tween(floatScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
            end
        else
            local x, y = clampMain(root.Position.X.Offset, root.Position.Y.Offset)
            root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            root.Visible = true
            tween(rootScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
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

    -- Resize grip (mouse + touch) ----------------------------------------
    local grip = new("TextButton", {
        Name = "ResizeGrip",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(MOBILE and 32 or 20, MOBILE and 32 or 20),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.5,
        AutoButtonColor = false,
        Text = "↘",
        Font = Enum.Font.GothamBold,
        TextSize = MOBILE and 16 or 12,
        TextColor3 = Theme.Text,
        ZIndex = 40,
        Parent = main,
    })
    corner(grip, 6)
    accentize(grip, "BackgroundColor3")

    local resizing = false
    local resizeInput, resizeStart, startSize, startCenter
    connect(grip.InputBegan, function(input)
        if not isPress(input) then return end
        resizing = true
        resizeInput = input
        resizeStart = input.Position
        startSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
        startCenter = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                c:Disconnect()
                resizing = false
            end
        end)
    end)
    connect(UIS.InputChanged, function(input)
        if not resizing then return end
        local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement
        local isTouch = input.UserInputType == Enum.UserInputType.Touch and input == resizeInput
        if not (isMouse or isTouch) then return end
        local d = input.Position - resizeStart
        applyChrome(startSize.X + d.X, startSize.Y + d.Y)
        local dx = root.Size.X.Offset - startSize.X
        local dy = root.Size.Y.Offset - startSize.Y
        local x, y = clampMain(startCenter.X + dx / 2, startCenter.Y + dy / 2)
        root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)

    task.defer(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        connect(cam:GetPropertyChangedSignal("ViewportSize"), function()
            if Window._destroyed then return end
            Window:SetSize(root.Size.X.Offset, root.Size.Y.Offset)
        end)
    end)

    -- Events -------------------------------------------------------------
    makeDraggable(topbar, root, clampMain)
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
    local function dropTree(rootInst)
        if not rootInst then return end
        for flag, obj in pairs(Library.Flags) do
            local r = obj._root
            if r then
                local ok, yes = pcall(function()
                    return r == rootInst or r:IsDescendantOf(rootInst)
                end)
                if ok and yes then
                    obj._dead = true
                    Library.Flags[flag] = nil
                end
            end
        end
    end

    local TAB_H = MOBILE and 44 or 36

    local function paintTab(tab)
        local btn = tab._btn
        for _, ch in ipairs(btn:GetChildren()) do
            ch:Destroy()
        end
        local asset = resolveIcon(tab.Icon)
        local showX = tab.Closeable ~= false
        corner(btn, 8)
        btn.Text = ""
        local left = 12
        if asset then
            tab._icon = new("ImageLabel", {
                Name = "Icon",
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, left, 0.5, 0),
                Size = UDim2.fromOffset(16, 16),
                BackgroundTransparency = 1,
                Image = asset,
                ImageColor3 = Theme.SubText,
                ScaleType = Enum.ScaleType.Fit,
                Parent = btn,
            })
            left = left + 24
        else
            tab._icon = nil
        end
        local right = showX and (MOBILE and 30 or 26) or 8
        tab._label = label({
            Name = "Name",
            Position = UDim2.new(0, left, 0, 0),
            Size = UDim2.new(1, -(left + right), 1, 0),
            Text = tab.Name,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.SubText,
            Parent = btn,
        })
        tab._indicator = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(3, 18),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
            Visible = Window._selected == tab,
            Parent = btn,
        })
        corner(tab._indicator, 2)
        if showX then
            local xbtn = new("TextButton", {
                Name = "Close",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -4, 0.5, 0),
                Size = UDim2.fromOffset(MOBILE and 24 or 18, MOBILE and 24 or 18),
                BackgroundColor3 = Theme.Danger,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "×",
                Font = Enum.Font.GothamBold,
                TextSize = MOBILE and 16 or 14,
                TextColor3 = Theme.SubText,
                TextTransparency = 0.4,
                ZIndex = 6,
                Parent = btn,
            })
            corner(xbtn, 5)
            xbtn.MouseEnter:Connect(function()
                tween(xbtn, 0.1, { BackgroundTransparency = 0, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 0 })
            end)
            xbtn.MouseLeave:Connect(function()
                tween(xbtn, 0.1, { BackgroundTransparency = 1, TextColor3 = Theme.SubText, TextTransparency = 0.4 })
            end)
            connect(xbtn.MouseButton1Click, function() tab:Destroy() end)
        end
    end

    -- small group header in the sidebar
    function Window:AddTabSection(text)
        sideOrder = sideOrder + 1
        local l = label({
            LayoutOrder = sideOrder,
            Size = UDim2.new(1, 0, 0, 22),
            Font = Enum.Font.GothamBold,
            TextSize = 10,
            TextColor3 = Theme.SubText,
            Text = "  " .. string.upper(tostring(text or "")),
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = sidebar,
        })
        local obj = {}
        bindRoot(obj, l)
        return obj
    end

    -- icon: Lucide name ("home", "alarm-clock"), id, or "rbxassetid://..."
    -- Closeable = false hides the X. tab:SetIcon(nil) / :ClearIcon() removes the icon.
    function Window:AddTab(name, icon)
        local closeable = true
        if type(name) == "table" then
            local o = name
            if o.Closeable == false then closeable = false end
            icon = o.Icon or o.Image or icon
            name = o.Name or o.Title or "Tab"
        end
        name = tostring(name or "Tab")

        local tab = { Name = name, Icon = icon, Closeable = closeable }

        sideOrder = sideOrder + 1
        local btn = new("TextButton", {
            LayoutOrder = sideOrder,
            Size = UDim2.new(1, 0, 0, TAB_H),
            BackgroundColor3 = Theme.Element,
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            Parent = sidebar,
        })

        local page = new("ScrollingFrame", {
            Name = name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = MOBILE and 4 or 3,
            ScrollBarImageColor3 = Theme.Accent,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
            Visible = false,
            Parent = pages,
        })
        accentize(page, "ScrollBarImageColor3")
        padding(page, 12, 12, 14, MOBILE and 20 or 14)
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })

        tab._btn, tab._page = btn, page
        paintTab(tab)

        connect(btn.MouseEnter, function()
            if Window._selected ~= tab and not tab._dead then
                tween(btn, 0.12, { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.45 })
            end
        end)
        connect(btn.MouseLeave, function()
            if Window._selected ~= tab and not tab._dead then
                tween(btn, 0.12, { BackgroundTransparency = 1 })
            end
        end)

        function tab:SetIcon(nextIcon)
            if nextIcon == false then nextIcon = nil end
            self.Icon = nextIcon
            paintTab(self)
            if Window._selected then Window._selected:Select() end
        end
        function tab:ClearIcon()
            self:SetIcon(nil)
        end
        function tab:SetName(nextName)
            self.Name = tostring(nextName or "Tab")
            self._page.Name = self.Name
            paintTab(self)
            if Window._selected then Window._selected:Select() end
        end
        function tab:Destroy()
            if self._dead then return end
            self._dead = true
            dropTree(self._page)
            local idx
            for i, t in ipairs(Window.Tabs) do
                if t == self then idx = i break end
            end
            if idx then table.remove(Window.Tabs, idx) end
            pcall(function() self._btn:Destroy() end)
            pcall(function() self._page:Destroy() end)
            if Window._selected == self then
                Window._selected = nil
                local nxt = Window.Tabs[idx] or Window.Tabs[#Window.Tabs]
                if nxt then nxt:Select() end
            end
        end

        function tab:Select()
            local previous = Window._selected
            Window._selected = self
            for _, t in ipairs(Window.Tabs) do
                local on = (t == self)
                if on and previous ~= self then
                    t._page.Position = UDim2.fromOffset(0, 10)
                    tween(t._page, 0.2, { Position = UDim2.fromOffset(0, 0) })
                end
                t._page.Visible = on
                if t._indicator then t._indicator.Visible = on end
                local textColor = on and Theme.Text or Theme.SubText
                tween(t._btn, 0.15, {
                    BackgroundColor3 = on and Theme.Accent or Theme.Hover,
                    BackgroundTransparency = on and 0.86 or 1,
                })
                if t._label then tween(t._label, 0.15, { TextColor3 = textColor }) end
                if t._icon then
                    tween(t._icon, 0.15, { ImageColor3 = on and Theme.Accent or Theme.SubText })
                end
                if t._indicator then t._indicator.BackgroundColor3 = Theme.Accent end
            end
        end

        local tabCtx = { container = page, scroller = page, order = 0 }
        attach(tab, tabCtx)

        -- AddSection(name, {Collapsed = false, Closeable = false})
        function tab:AddSection(secName, secOpts)
            if type(secOpts) ~= "table" then secOpts = {} end
            local frame = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Section,
                BorderSizePixel = 0,
                LayoutOrder = nextOrder(tabCtx),
                Parent = page,
            })
            corner(frame, 10)
            stroke(frame, Theme.Outline, 1).Transparency = 0.3
            padding(frame, 10, 8, 10, 10)
            new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })

            local headRow = new("TextButton", {
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, MOBILE and 28 or 22),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                Parent = frame,
            })
            local pip = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(3, 12),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Parent = headRow,
            })
            corner(pip, 2)
            accentize(pip, "BackgroundColor3")
            local head = label({
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -52, 1, 0),
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Text,
                Text = string.upper(secName or "Section"),
                TextTruncate = Enum.TextTruncate.AtEnd,
                Parent = headRow,
            })
            local chevron = new("ImageLabel", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, secOpts.Closeable and -22 or -2, 0.5, 0),
                Size = UDim2.fromOffset(14, 14),
                BackgroundTransparency = 1,
                Image = resolveIcon("chevrondown") or "",
                ImageColor3 = Theme.SubText,
                Parent = headRow,
            })
            local body = new("Frame", {
                LayoutOrder = 1,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Parent = frame,
            })
            new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

            local collapsed = secOpts.Collapsed and true or false
            local function applyCollapse(animate)
                body.Visible = not collapsed
                tween(chevron, animate and 0.15 or 0, { Rotation = collapsed and -90 or 0 })
            end
            applyCollapse(false)
            connect(headRow.MouseButton1Click, function()
                collapsed = not collapsed
                applyCollapse(true)
            end)

            local section = {}
            function section:SetName(n)
                secName = n
                head.Text = string.upper(tostring(n or "Section"))
            end
            function section:Collapse() collapsed = true; applyCollapse(true) end
            function section:Expand() collapsed = false; applyCollapse(true) end
            function section:Destroy()
                dropTree(frame)
                if frame.Parent then frame:Destroy() end
            end
            attach(section, { container = body, scroller = page, order = 0 })

            if secOpts.Closeable then
                local kill = new("TextButton", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(MOBILE and 24 or 18, MOBILE and 24 or 18),
                    BackgroundTransparency = 1,
                    Text = "×",
                    Font = Enum.Font.GothamBold,
                    TextSize = 14,
                    TextColor3 = Theme.SubText,
                    ZIndex = 3,
                    Parent = headRow,
                })
                connect(kill.MouseButton1Click, function() section:Destroy() end)
            end
            return section
        end

        connect(btn.MouseButton1Click, function()
            if not tab._dead then tab:Select() end
        end)

        Window.Tabs[#Window.Tabs + 1] = tab
        if #Window.Tabs == 1 then tab:Select() end
        return tab
    end

    onAccent(function()
        if not Window._destroyed and Window._selected and not Window._selected._dead then
            Window._selected:Select()
        end
    end)

    function Window:RemoveTab(nameOrTab)
        local tab = nameOrTab
        if type(nameOrTab) ~= "table" then
            for _, t in ipairs(self.Tabs) do
                if t.Name == nameOrTab then tab = t break end
            end
        end
        if type(tab) == "table" and tab.Destroy then tab:Destroy() end
    end

    function Window:SelectTab(nameOrTab)
        local tab = nameOrTab
        if type(nameOrTab) ~= "table" then
            for _, t in ipairs(self.Tabs) do
                if t.Name == nameOrTab then tab = t break end
            end
        end
        if type(tab) == "table" and tab.Select and not tab._dead then tab:Select() end
    end

    function Window:AddSettingsTab()
        if self._settingsTab and not self._settingsTab._dead then
            return self._settingsTab
        end
        local tab = self:AddTab({ Name = "Settings", Icon = "settings", Closeable = false })
        self._settingsTab = tab
        local sec = tab:AddSection("Config")
        local autoName = Library:GetAutoload()
        local chosen = (autoName ~= "" and autoName) or "default"
        local autoOn = autoName ~= ""

        local nameBox = sec:AddTextbox({
            Name = "Config name",
            Default = chosen,
            Placeholder = "default",
            NoSave = true,
            Callback = function(text)
                chosen = cleanConfigName(text, "default")
                if chosen == "" then chosen = "default" end
                if autoOn then Library:SetAutoload(chosen) end
            end,
        })

        local savedDrop
        local function refreshList()
            local list = Library:ListConfigs()
            if savedDrop then savedDrop:Refresh(list, true) end
            return list
        end

        savedDrop = sec:AddDropdown({
            Name = "Saved configs",
            Options = Library:ListConfigs(),
            Default = chosen,
            NoSave = true,
            Callback = function(v)
                chosen = tostring(v)
                nameBox:Set(chosen)
            end,
        })

        sec:AddButton({
            Name = "Save config",
            Icon = "save",
            Callback = function()
                local ok, clean = Window:SaveConfig(chosen)
                refreshList()
                if clean and savedDrop then savedDrop:Set(clean, true) end
                Window:Notify({
                    Title = "Settings",
                    Content = ok and ("Saved " .. tostring(clean)) or "Could not save",
                    Type = ok and "success" or "error",
                    Duration = 3,
                })
            end,
        })
        sec:AddButton({
            Name = "Load config",
            Icon = "download",
            Callback = function()
                local ok = Window:LoadConfig(chosen)
                Window:Notify({
                    Title = "Settings",
                    Content = ok and ("Loaded " .. chosen) or "Nothing saved with that name",
                    Type = ok and "success" or "warning",
                    Duration = 3,
                })
            end,
        })
        sec:AddButton({
            Name = "Delete config",
            Icon = "trash2",
            Callback = function()
                Window:DeleteConfig(chosen)
                refreshList()
                Window:Notify({ Title = "Settings", Content = "Deleted " .. chosen, Duration = 2 })
            end,
        })
        sec:AddToggle({
            Name = "Autoload this config",
            Default = autoOn,
            NoSave = true,
            Callback = function(v)
                autoOn = v and true or false
                Library:SetAutoload(autoOn and chosen or "")
            end,
        })
        sec:AddLabel("Saves every toggle, slider, dropdown, textbox, keybind and color, plus window size and position.")

        local menu = tab:AddSection("Menu")
        menu:AddKeybind({
            Name = "Menu key",
            Flag = "AzureMenuKey",
            Default = Window.ToggleKey,
            Changed = function(key) if key then Window:SetToggleKey(key) end end,
        })
        menu:AddToggle({
            Name = "Logo button on minimize",
            Flag = "AzureFloatButton",
            Default = Window.FloatEnabled,
            Callback = function(v) Window:SetFloatButton(v) end,
        })
        menu:AddColorPicker({
            Name = "Accent color",
            Flag = "AzureAccent",
            Default = Theme.Accent,
            Callback = function(c) Library:SetAccent(c) end,
        })
        menu:AddButton({
            Name = "Unload UI",
            Icon = "power",
            Callback = function() Library:Unload() end,
        })

        local win = tab:AddSection("Window", { Collapsed = true })
        win:AddLabel("Drag the top bar to move. Drag the corner to resize. The × on a tab removes it.")
        win:AddButton({
            Name = "Reset window size",
            Icon = "maximize",
            Callback = function()
                local v = screenSize()
                local w = math.clamp(MOBILE and 380 or 560, 300, v.X - 12)
                local h = math.clamp(MOBILE and math.floor(v.Y * 0.72) or 450, 250, v.Y - 12)
                Window:SetSize(w, h)
                root.Position = UDim2.fromOffset(math.floor(v.X / 2), math.floor(v.Y / 2))
                local x, y = clampMain(root.Position.X.Offset, root.Position.Y.Offset)
                root.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
            end,
        })
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
    if env.AzureUI_KeyGui then pcall(function() env.AzureUI_KeyGui:Destroy() end) end
    env.AzureUI_KeyGui = nil
    table.clear(Library.Windows)
    table.clear(Library.Flags)
    table.clear(accentFns)
    Library.CurrentWindow = nil
    Library.Listening = false
    env.AzureUI_Cleanup = nil
end

env.AzureUI_Cleanup = function() Library:Unload() end

----------------------------------------------------------------------
-- USAGE EXAMPLE (you can delete from here down)
----------------------------------------------------------------------
--[[
-- 1) KEY SYSTEM (optional) ------------------------------------------------
-- Luarmor:
local ok, key, info = Library:KeySystem({
    Title = "azure.lol", Subtitle = "key required",
    Provider = "Luarmor", ScriptId = "your_script_id",
    GetKeyLink = "https://your-site.com/getkey",
    Discord = "https://discord.gg/yourinvite",
})
-- Platoboost:
-- Library:KeySystem({ Provider = "Platoboost", Service = 1234, Secret = "your_secret", UseNonce = false })
-- Static list:
-- Library:KeySystem({ Provider = "Static", Keys = { "AZURE-1234", "AZURE-5678" } })
-- Your own function:
-- Library:KeySystem({ Provider = "Custom", Validate = function(key, hwid) return key == "abc", "Welcome!" end })
-- Any website API:
-- Library:KeySystem({ Provider = "Http", Url = "https://api.site.com/check?key={key}&hwid={hwid}",
--     SuccessField = "valid", MessageField = "message" })
if not ok then return end

-- 2) WINDOW ------------------------------------------------------------------
local Window = Library:CreateWindow({
    Title = "azure.lol",
    Subtitle = "v2.0",
    Icon = 127041730095194,          -- your logo
    ToggleKey = Enum.KeyCode.LeftControl,
    -- FloatButton = true,           -- forces the logo button on PC too
    -- Profile = false,              -- hides the player card in the sidebar
    -- Theme = { Accent = Color3.fromRGB(170, 85, 255) },
})

Window:AddTabSection("Features")
local Principal = Window:AddTab("Main", "home") -- Lucide name, or an id: 10709751939

local geral = Principal:AddSection("General")
geral:AddToggle({
    Name = "Enable feature", Description = "Turns the feature on",
    Flag = "EnableFeature", Default = false,
    Callback = function(v) print("Toggle:", v) end,
})
geral:AddSlider({
    Name = "Speed", Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
    Callback = function(v) print("Slider:", v) end,
})
geral:AddDropdown({
    Name = "Mode", Options = { "Normal", "Fast", "Safe" }, Default = "Normal",
    Callback = function(v) print("Mode:", v) end,
})
geral:AddDropdown({
    Name = "Targets", Options = { "Players", "NPCs", "Bosses" }, Multi = true, Default = { "Players" },
    Callback = function(list) print("Targets:", table.concat(list, ", ")) end,
})
geral:AddColorPicker({ Name = "ESP color", Default = Color3.fromRGB(255, 80, 80), Callback = print })
geral:AddButton({
    Name = "Show notification",
    Callback = function()
        Window:Notify({ Title = "azure.lol", Content = "Working perfectly!", Type = "success", Duration = 3 })
    end,
})

Window:AddSettingsTab()
Window:TryAutoLoad()
]]
return Library