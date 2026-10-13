--[[
    AzureUI — custom Roblox / Luau UI

    • Drag the top bar (mouse and touch). Drag the bottom-right corner to resize.
    • LeftControl minimizes. The round logo brings the window back.
    • Tabs: Lucide name ("home", "alarm-clock") or a Roblox asset id.
      tab:SetIcon("settings")  tab:ClearIcon()  tab:SetName("New")  tab:Destroy()
    • Every control has :Destroy(). Sections too.
    • Window:AddSettingsTab() saves toggles, sliders, dropdowns, textboxes and keybinds.
      Call Window:TryAutoLoad() after you finish building the UI.
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
    Flags = {},
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
    return game:GetService("CoreGui")
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
    return MOBILE and 44 or 34
end

local function hasFS()
    return type(writefile) == "function" and type(readfile) == "function"
end

local function ensureFolder()
    if type(makefolder) ~= "function" then return end
    local exists = type(isfolder) == "function" and isfolder(CONFIG_FOLDER)
    if not exists then pcall(makefolder, CONFIG_FOLDER) end
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
    bindRoot(obj, lbl)
    return obj
end

function Elements.Button(ctx, opts)
    if type(opts) == "string" then opts = { Name = opts } end
    opts = opts or {}
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, rowH()),
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
    bindRoot(obj, btn)
    return obj
end

function Elements.Toggle(ctx, opts)
    opts = opts or {}
    local value = opts.Default and true or false

    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, rowH()),
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

    connect(row.MouseButton1Click, function()
        if obj._dead then return end
        obj:Set(not obj.Value)
    end)
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
        Size = UDim2.new(1, 0, 0, MOBILE and 58 or 48),
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
        Position = UDim2.new(0, 10, 1, MOBILE and -18 or -14),
        Size = UDim2.new(1, -20, 0, MOBILE and 8 or 6),
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
    knob.Size = UDim2.fromOffset(MOBILE and 18 or 12, MOBILE and 18 or 12)
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
    bindFlag(obj, row, opts, "Slider")
    return obj
end

function Elements.Dropdown(ctx, opts)
    opts = opts or {}
    local options = opts.Options or {}
    local name = opts.Name or "Dropdown"
    local obj = { Value = opts.Default, Options = options }
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
                Size = UDim2.new(1, 0, 0, MOBILE and 40 or 28),
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
    bindFlag(obj, wrap, opts, "Dropdown")
    return obj
end

function Elements.Textbox(ctx, opts)
    opts = opts or {}
    local tall = MOBILE
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, tall and 68 or rowH()),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)

    label({
        Position = UDim2.new(0, 10, 0, tall and 6 or 0),
        Size = tall and UDim2.new(1, -16, 0, 18) or UDim2.new(1, -150, 1, 0),
        Text = opts.Name or "Textbox",
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = row,
    })

    local box = new("TextBox", {
        AnchorPoint = tall and Vector2.new(0, 1) or Vector2.new(1, 0.5),
        Position = tall and UDim2.new(0, 8, 1, -8) or UDim2.new(1, -6, 0.5, 0),
        Size = tall and UDim2.new(1, -16, 0, 30) or UDim2.fromOffset(130, 24),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "...",
        PlaceholderColor3 = Theme.SubText,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        TextSize = MOBILE and 14 or 12,
        TextColor3 = Theme.Text,
        Parent = row,
    })
    corner(box, 5)
    padding(box, 6, 0, 6, 0)

    connect(box.FocusLost, function(enter)
        if obj._dead then return end
        fire(opts.Callback, box.Text, enter)
    end)

    local obj = {}
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

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, rowH()),
        BackgroundColor3 = Theme.Element,
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(ctx),
        Parent = ctx.container,
    })
    corner(row, 6)

    label({
        Position = UDim2.new(0, 10, 0, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Text = opts.Name or "Keybind",
        Parent = row,
    })

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(MOBILE and 104 or 90, MOBILE and 28 or 24),
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
    local maxW = math.min(opts.Width or (MOBILE and 440 or 560), math.max(280, vp.X - 8))
    local maxH = math.min(opts.Height or (MOBILE and math.floor(vp.Y * 0.78) or 460), math.max(240, vp.Y - 8))
    local margin = MOBILE and 10 or 24
    local width = math.clamp(vp.X - margin * 2, MOBILE and 280 or 340, maxW)
    local height = math.clamp(vp.Y - (MOBILE and 64 or 72), 240, maxH)
    local sidebarW = width < 480 and (MOBILE and 116 or 108) or 142
    local TOPBAR = MOBILE and 48 or 40

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
        Size = UDim2.new(1, MOBILE and -132 or -118, 1, -2),
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
            Size = UDim2.fromOffset(MOBILE and 36 or 28, MOBILE and 32 or 26),
            BackgroundColor3 = Theme.Element,
            AutoButtonColor = false,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = MOBILE and 18 or 16,
            TextColor3 = Theme.Text,
            Parent = topbar,
        })
        corner(b, 6)
        hover(b, Theme.Element, hoverColor)
        return b
    end
    local minBtn = topButton("–", MOBILE and -50 or -42, Theme.Hover)
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
    local sideBorder = new("Frame", {
        Name = "SideBorder",
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

    -- Clamp + resize ------------------------------------------------------
    local function applyChrome(w, h)
        local v = screenSize()
        local minW = MOBILE and 270 or 320
        local minH = 230
        w = math.clamp(math.floor(w + 0.5), minW, math.max(minW, v.X - 8))
        h = math.clamp(math.floor(h + 0.5), minH, math.max(minH, v.Y - 8))
        local sw = (w < 480) and (MOBILE and 116 or 108) or 142
        sidebarW = sw
        sidebar.Position = UDim2.fromOffset(0, TOPBAR)
        sidebar.Size = UDim2.new(0, sw, 1, -TOPBAR)
        sideBorder.Position = UDim2.new(0, sw - 1, 0, TOPBAR)
        sideBorder.Size = UDim2.new(0, 1, 1, -TOPBAR)
        pages.Position = UDim2.fromOffset(sw, TOPBAR)
        pages.Size = UDim2.new(1, -sw, 1, -TOPBAR)
        main.Size = UDim2.fromOffset(w, h)
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
        local w = main.Size.X.Offset
        local h = main.Size.Y.Offset
        local minX = w / 2
        local maxX = math.max(minX, v.X - w / 2)
        local minY = h / 2
        local maxY = math.max(minY, v.Y - h / 2)
        return math.clamp(x, minX, maxX), math.clamp(y, minY, maxY)
    end

    function Window:SetSize(w, h)
        applyChrome(w, h)
        local x, y = clampMain(main.Position.X.Offset, main.Position.Y.Offset)
        main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end

    function Window:GetState()
        return {
            x = main.Position.X.Offset,
            y = main.Position.Y.Offset,
            w = main.Size.X.Offset,
            h = main.Size.Y.Offset,
        }
    end

    function Window:SetState(state)
        if type(state) ~= "table" then return end
        if tonumber(state.w) and tonumber(state.h) then
            applyChrome(tonumber(state.w), tonumber(state.h))
        end
        if tonumber(state.x) and tonumber(state.y) then
            local x, y = clampMain(tonumber(state.x), tonumber(state.y))
            main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
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

    -- Resize grip (mouse + touch) ----------------------------------------
    local grip = new("TextButton", {
        Name = "ResizeGrip",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -4, 1, -4),
        Size = UDim2.fromOffset(MOBILE and 34 or 22, MOBILE and 34 or 22),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.25,
        AutoButtonColor = false,
        Text = "↘",
        Font = Enum.Font.GothamBold,
        TextSize = MOBILE and 16 or 13,
        TextColor3 = Theme.Text,
        ZIndex = 40,
        Parent = main,
    })
    corner(grip, 7)

    local resizing = false
    local resizeInput, resizeStart, startSize, startCenter
    connect(grip.InputBegan, function(input)
        if not isPress(input) then return end
        resizing = true
        resizeInput = input
        resizeStart = input.Position
        startSize = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
        startCenter = Vector2.new(main.Position.X.Offset, main.Position.Y.Offset)
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
        local dx = main.Size.X.Offset - startSize.X
        local dy = main.Size.Y.Offset - startSize.Y
        local x, y = clampMain(startCenter.X + dx / 2, startCenter.Y + dy / 2)
        main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)

    task.defer(function()
        local cam = workspace.CurrentCamera
        if not cam then return end
        connect(cam:GetPropertyChangedSignal("ViewportSize"), function()
            if Window._destroyed then return end
            Window:SetSize(main.Size.X.Offset, main.Size.Y.Offset)
        end)
    end)

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
    local function dropTree(root)
        if not root then return end
        for flag, obj in pairs(Library.Flags) do
            local r = obj._root
            if r then
                local ok, yes = pcall(function()
                    return r == root or r:IsDescendantOf(root)
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
        corner(btn, 6)
        btn.Text = ""
        local left = 10
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
            left = left + 22
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
            Position = UDim2.new(0, 3, 0.5, 0),
            Size = UDim2.fromOffset(3, 16),
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
                Position = UDim2.new(1, -3, 0.5, 0),
                Size = UDim2.fromOffset(MOBILE and 26 or 20, MOBILE and 26 or 20),
                BackgroundColor3 = Theme.Element,
                BackgroundTransparency = 0.35,
                AutoButtonColor = false,
                Text = "×",
                Font = Enum.Font.GothamBold,
                TextSize = MOBILE and 16 or 14,
                TextColor3 = Theme.SubText,
                ZIndex = 6,
                Parent = btn,
            })
            corner(xbtn, 5)
            connect(xbtn.MouseButton1Click, function() tab:Destroy() end)
        end
    end

    -- icon: nome Lucide ("home", "alarm-clock"), id, ou "rbxassetid://..."
    -- Closeable = false esconde o X. tab:SetIcon(nil) / :ClearIcon() tira o ícone.
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

        local btn = new("TextButton", {
            LayoutOrder = #Window.Tabs + 1,
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
        padding(page, 10, 10, 12, MOBILE and 18 or 12)
        new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })

        tab._btn, tab._page = btn, page
        paintTab(tab)

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
            Window._selected = self
            for _, t in ipairs(Window.Tabs) do
                local on = (t == self)
                t._page.Visible = on
                if t._indicator then t._indicator.Visible = on end
                local textColor = on and Theme.Text or Theme.SubText
                tween(t._btn, 0.15, {
                    BackgroundTransparency = on and 0 or 1,
                    TextColor3 = textColor,
                })
                if t._label then tween(t._label, 0.15, { TextColor3 = textColor }) end
                if t._icon then
                    tween(t._icon, 0.15, { ImageColor3 = on and Theme.Accent or Theme.SubText })
                end
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
            local headRow = new("Frame", {
                LayoutOrder = 0,
                Size = UDim2.new(1, 0, 0, MOBILE and 24 or 18),
                BackgroundTransparency = 1,
                Parent = frame,
            })
            local head = label({
                Size = UDim2.new(1, -28, 1, 0),
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Accent,
                Text = string.upper(secName or "Section"),
                Parent = headRow,
            })
            local kill = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 4, 0.5, 0),
                Size = UDim2.fromOffset(MOBILE and 24 or 18, MOBILE and 24 or 18),
                BackgroundTransparency = 1,
                Text = "×",
                Font = Enum.Font.GothamBold,
                TextSize = 14,
                TextColor3 = Theme.SubText,
                Parent = headRow,
            })
            local section = {}
            function section:SetName(n)
                secName = n
                head.Text = string.upper(tostring(n or "Section"))
            end
            function section:Destroy()
                dropTree(frame)
                if frame.Parent then frame:Destroy() end
            end
            attach(section, { container = frame, scroller = page, order = 0 })
            connect(kill.MouseButton1Click, function() section:Destroy() end)
            return section
        end

        connect(btn.MouseButton1Click, function()
            if not tab._dead then tab:Select() end
        end)

        Window.Tabs[#Window.Tabs + 1] = tab
        if #Window.Tabs == 1 then tab:Select() end
        return tab
    end

    function Window:RemoveTab(nameOrTab)
        local tab = nameOrTab
        if type(nameOrTab) ~= "table" then
            for _, t in ipairs(self.Tabs) do
                if t.Name == nameOrTab then tab = t break end
            end
        end
        if type(tab) == "table" and tab.Destroy then tab:Destroy() end
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
            Callback = function()
                local ok, clean = Window:SaveConfig(chosen)
                refreshList()
                if clean and savedDrop then savedDrop:Set(clean, true) end
                Window:Notify({
                    Title = "Settings",
                    Content = ok and ("Saved " .. tostring(clean)) or "Could not save",
                    Duration = 3,
                })
            end,
        })
        sec:AddButton({
            Name = "Load config",
            Callback = function()
                local ok = Window:LoadConfig(chosen)
                Window:Notify({
                    Title = "Settings",
                    Content = ok and ("Loaded " .. chosen) or "Nothing saved with that name",
                    Duration = 3,
                })
            end,
        })
        sec:AddButton({
            Name = "Delete config",
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
        sec:AddLabel("Saves every toggle, slider, dropdown, textbox and keybind, plus window size and position.")

        local win = tab:AddSection("Window")
        win:AddLabel("Drag the top bar to move. Drag the blue corner to resize. The × on a tab or section removes it.")
        win:AddButton({
            Name = "Reset window size",
            Callback = function()
                local v = screenSize()
                local w = math.clamp(MOBILE and 380 or 540, 300, v.X - 12)
                local h = math.clamp(MOBILE and math.floor(v.Y * 0.72) or 440, 250, v.Y - 12)
                Window:SetSize(w, h)
                main.Position = UDim2.fromOffset(math.floor(v.X / 2), math.floor(v.Y / 2))
                local x, y = clampMain(main.Position.X.Offset, main.Position.Y.Offset)
                main.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
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
    table.clear(Library.Windows)
    table.clear(Library.Flags)
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

local Principal = Window:AddTab("Main", "home") -- Lucide name, or an id: 10709751939
-- Principal:SetIcon("swords")   -- troca o icone
-- Principal:ClearIcon()         -- remove o icone
-- Principal:SetName("Combat")
-- Principal:Destroy()           -- apaga a tab (o X da sidebar tambem apaga)
-- Window:RemoveTab("Main")

local geral = Principal:AddSection("General")
local feature = geral:AddToggle({
    Name = "Enable feature",
    Flag = "EnableFeature", -- chave salva na config. Sem Flag, usa o Name.
    Default = false,
    Callback = function(v) print("Toggle:", v) end,
})
-- feature:Destroy()
-- geral:Destroy()
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

local Config = Window:AddTab({ Name = "Menu", Icon = "sliders" })
local menu = Config:AddSection("Menu")
menu:AddKeybind({
    Name = "Menu key",
    Flag = "MenuKey",
    Default = Enum.KeyCode.LeftControl,
    Changed = function(key) if key then Window:SetToggleKey(key) end end,
})
menu:AddToggle({
    Name = "Logo button on minimize",
    Flag = "FloatButton",
    Default = Window.FloatEnabled,
    Callback = function(v) Window:SetFloatButton(v) end,
})
menu:AddButton({
    Name = "Unload UI",
    Callback = function() Library:Unload() end,
})

-- Save / load every control + window size. Call TryAutoLoad AFTER the UI is built.
Window:AddSettingsTab()
Window:TryAutoLoad()

Window:Notify({ Title = "azure.lol", Content = "Drag the corner to resize. Settings saves the config.", Duration = 4 })
]]
return Library