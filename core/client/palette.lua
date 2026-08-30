
local RESOURCE = GetCurrentResourceName()

local SAMPLE_SPOT = vector3(0.0, 0.0, -200.0)

local CEILING = 255

local palette = nil
local sampling = false

local PAINTS = {
    [0] = { name = "Black", class = "metallic", hex = "#0d1116" },
    [1] = { name = "Graphite Black", class = "metallic", hex = "#1c1d21" },
    [2] = { name = "Black Steal", class = "metallic", hex = "#32383d" },
    [3] = { name = "Dark Silver", class = "metallic", hex = "#454b4f" },
    [4] = { name = "Silver", class = "metallic", hex = "#999da0" },
    [5] = { name = "Blue Silver", class = "metallic", hex = "#c2c4c6" },
    [6] = { name = "Steel Gray", class = "metallic", hex = "#979a97" },
    [7] = { name = "Shadow Silver", class = "metallic", hex = "#637380" },
    [8] = { name = "Stone Silver", class = "metallic", hex = "#63625c" },
    [9] = { name = "Midnight Silver", class = "metallic", hex = "#3c3f47" },
    [10] = { name = "Gun Metal", class = "metallic", hex = "#444e54" },
    [11] = { name = "Anthracite Grey", class = "metallic", hex = "#1d2129" },
    [12] = { name = "Black", class = "matte", hex = "#13181f" },
    [13] = { name = "Gray", class = "matte", hex = "#26282a" },
    [14] = { name = "Light Grey", class = "matte", hex = "#515554" },
    [15] = { name = "Black", class = "util", hex = "#151921" },
    [16] = { name = "Black Poly", class = "util", hex = "#1e2429" },
    [17] = { name = "Dark Silver", class = "util", hex = "#333a3c" },
    [18] = { name = "Silver", class = "util", hex = "#8c9095" },
    [19] = { name = "Gun Metal", class = "util", hex = "#39434d" },
    [20] = { name = "Shadow Silver", class = "util", hex = "#506272" },
    [21] = { name = "Black", class = "worn", hex = "#1e232f" },
    [22] = { name = "Graphite", class = "worn", hex = "#363a3f" },
    [23] = { name = "Silver Grey", class = "worn", hex = "#a0a199" },
    [24] = { name = "Silver", class = "worn", hex = "#d3d3d3" },
    [25] = { name = "Blue Silver", class = "worn", hex = "#b7bfca" },
    [26] = { name = "Shadow Silver", class = "worn", hex = "#778794" },
    [27] = { name = "Red", class = "metallic", hex = "#c00e1a" },
    [28] = { name = "Torino Red", class = "metallic", hex = "#da1918" },
    [29] = { name = "Formula Red", class = "metallic", hex = "#b6111b" },
    [30] = { name = "Blaze Red", class = "metallic", hex = "#a51e23" },
    [31] = { name = "Graceful Red", class = "metallic", hex = "#7b1a22" },
    [32] = { name = "Garnet Red", class = "metallic", hex = "#8e1b1f" },
    [33] = { name = "Desert Red", class = "metallic", hex = "#6f1818" },
    [34] = { name = "Cabernet Red", class = "metallic", hex = "#49111d" },
    [35] = { name = "Candy Red", class = "metallic", hex = "#b60f25" },
    [36] = { name = "Sunrise Orange", class = "metallic", hex = "#d44a17" },
    [37] = { name = "Classic Gold", class = "metallic", hex = "#c2944f" },
    [38] = { name = "Orange", class = "metallic", hex = "#f78616" },
    [39] = { name = "Red", class = "matte", hex = "#cf1f21" },
    [40] = { name = "Dark Red", class = "matte", hex = "#732021" },
    [41] = { name = "Orange", class = "matte", hex = "#f27d20" },
    [42] = { name = "Yellow", class = "matte", hex = "#ffc91f" },
    [43] = { name = "Red", class = "util", hex = "#9c1016" },
    [44] = { name = "Bright Red", class = "util", hex = "#de0f18" },
    [45] = { name = "Garnet Red", class = "util", hex = "#8f1e17" },
    [46] = { name = "Red", class = "worn", hex = "#a94744" },
    [47] = { name = "Golden Red", class = "worn", hex = "#b16c51" },
    [48] = { name = "Dark Red", class = "worn", hex = "#371c25" },
    [49] = { name = "Dark Green", class = "metallic", hex = "#132428" },
    [50] = { name = "Racing Green", class = "metallic", hex = "#122e2b" },
    [51] = { name = "Sea Green", class = "metallic", hex = "#12383c" },
    [52] = { name = "Olive Green", class = "metallic", hex = "#31423f" },
    [53] = { name = "Green", class = "metallic", hex = "#155c2d" },
    [54] = { name = "Gasoline Blue Green", class = "metallic", hex = "#1b6770" },
    [55] = { name = "Lime Green", class = "matte", hex = "#66b81f" },
    [56] = { name = "Dark Green", class = "util", hex = "#22383e" },
    [57] = { name = "Green", class = "util", hex = "#1d5a3f" },
    [58] = { name = "Dark Green", class = "worn", hex = "#2d423f" },
    [59] = { name = "Green", class = "worn", hex = "#45594b" },
    [60] = { name = "Sea Wash", class = "worn", hex = "#65867f" },
    [61] = { name = "Midnight Blue", class = "metallic", hex = "#222e46" },
    [62] = { name = "Dark Blue", class = "metallic", hex = "#233155" },
    [63] = { name = "Saxony Blue", class = "metallic", hex = "#304c7e" },
    [64] = { name = "Blue", class = "metallic", hex = "#47578f" },
    [65] = { name = "Mariner Blue", class = "metallic", hex = "#637ba7" },
    [66] = { name = "Harbor Blue", class = "metallic", hex = "#394762" },
    [67] = { name = "Diamond Blue", class = "metallic", hex = "#d6e7f1" },
    [68] = { name = "Surf Blue", class = "metallic", hex = "#76afbe" },
    [69] = { name = "Nautical Blue", class = "metallic", hex = "#345e72" },
    [70] = { name = "Bright Blue", class = "metallic", hex = "#0b9cf1" },
    [71] = { name = "Purple Blue", class = "metallic", hex = "#2f2d52" },
    [72] = { name = "Spinnaker Blue", class = "metallic", hex = "#282c4d" },
    [73] = { name = "Ultra Blue", class = "metallic", hex = "#2354a1" },
    [74] = { name = "Bright Blue", class = "metallic", hex = "#6ea3c6" },
    [75] = { name = "Dark Blue", class = "util", hex = "#112552" },
    [76] = { name = "Midnight Blue", class = "util", hex = "#1b203e" },
    [77] = { name = "Blue", class = "util", hex = "#275190" },
    [78] = { name = "Sea Foam Blue", class = "util", hex = "#608592" },
    [79] = { name = "Lightning Blue", class = "util", hex = "#2446a8" },
    [80] = { name = "Maui Blue Poly", class = "util", hex = "#4271e1" },
    [81] = { name = "Bright Blue", class = "util", hex = "#3b39e0" },
    [82] = { name = "Dark Blue", class = "matte", hex = "#1f2852" },
    [83] = { name = "Blue", class = "matte", hex = "#253aa7" },
    [84] = { name = "Midnight Blue", class = "matte", hex = "#1c3551" },
    [85] = { name = "Dark Blue", class = "worn", hex = "#4c5f81" },
    [86] = { name = "Blue", class = "worn", hex = "#58688e" },
    [87] = { name = "Light Blue", class = "worn", hex = "#74b5d8" },
    [88] = { name = "Taxi Yellow", class = "metallic", hex = "#ffcf20" },
    [89] = { name = "Race Yellow", class = "metallic", hex = "#fbe212" },
    [90] = { name = "Bronze", class = "metallic", hex = "#916532" },
    [91] = { name = "Yellow Bird", class = "metallic", hex = "#e0e13d" },
    [92] = { name = "Lime", class = "metallic", hex = "#98d223" },
    [93] = { name = "Champagne", class = "metallic", hex = "#9b8c78" },
    [94] = { name = "Pueblo Beige", class = "metallic", hex = "#503218" },
    [95] = { name = "Dark Ivory", class = "metallic", hex = "#473f2b" },
    [96] = { name = "Choco Brown", class = "metallic", hex = "#221b19" },
    [97] = { name = "Golden Brown", class = "metallic", hex = "#653f23" },
    [98] = { name = "Light Brown", class = "metallic", hex = "#775c3e" },
    [99] = { name = "Straw Beige", class = "metallic", hex = "#ac9975" },
    [100] = { name = "Moss Brown", class = "metallic", hex = "#6c6b4b" },
    [101] = { name = "Biston Brown", class = "metallic", hex = "#402e2b" },
    [102] = { name = "Beechwood", class = "metallic", hex = "#a4965f" },
    [103] = { name = "Dark Beechwood", class = "metallic", hex = "#46231a" },
    [104] = { name = "Choco Orange", class = "metallic", hex = "#752b19" },
    [105] = { name = "Beach Sand", class = "metallic", hex = "#bfae7b" },
    [106] = { name = "Sun Bleeched Sand", class = "metallic", hex = "#dfd5b2" },
    [107] = { name = "Cream", class = "metallic", hex = "#f7edd5" },
    [108] = { name = "Brown", class = "util", hex = "#3a2a1b" },
    [109] = { name = "Medium Brown", class = "util", hex = "#785f33" },
    [110] = { name = "Light Brown", class = "util", hex = "#b5a079" },
    [111] = { name = "White", class = "metallic", hex = "#fffff6" },
    [112] = { name = "Frost White", class = "metallic", hex = "#eaeaea" },
    [113] = { name = "Honey Beige", class = "worn", hex = "#b0ab94" },
    [114] = { name = "Brown", class = "worn", hex = "#453831" },
    [115] = { name = "Dark Brown", class = "worn", hex = "#2a282b" },
    [116] = { name = "Straw Beige", class = "worn", hex = "#726c57" },
    [117] = { name = "Brushed Steel", class = "misc", hex = "#6a747c" },
    [118] = { name = "Brushed Black Steel", class = "misc", hex = "#354158" },
    [119] = { name = "Brushed Aluminium", class = "misc", hex = "#9ba0a8" },
    [120] = { name = "Chrome", class = "misc", hex = "#b4bac2", stops = { "#ffffff", "#63666b", "#e1e9f3", "#7e8288", "#ffffff", "#999ea5" } },
    [121] = { name = "Off White", class = "worn", hex = "#eae6de" },
    [122] = { name = "Off White", class = "util", hex = "#dfddd0" },
    [123] = { name = "Orange", class = "worn", hex = "#f2ad2e" },
    [124] = { name = "Light Orange", class = "worn", hex = "#f9a458" },
    [125] = { name = "Securicor Green", class = "metallic", hex = "#83c566" },
    [126] = { name = "Taxi Yellow", class = "worn", hex = "#f1cc40" },
    [127] = { name = "Police Car Blue", class = "misc", hex = "#4cc3da" },
    [128] = { name = "Green", class = "matte", hex = "#4e6443" },
    [129] = { name = "Brown", class = "matte", hex = "#bcac8f" },
    [130] = { name = "Orange", class = "worn", hex = "#f8b658" },
    [131] = { name = "White", class = "matte", hex = "#fcf9f1" },
    [132] = { name = "White", class = "worn", hex = "#fffffb" },
    [133] = { name = "Olive Army Green", class = "worn", hex = "#81844c" },
    [134] = { name = "Pure White", class = "misc", hex = "#ffffff" },
    [135] = { name = "Hot Pink", class = "misc", hex = "#f21f99" },
    [136] = { name = "Salmon Pink", class = "misc", hex = "#fdd6cd" },
    [137] = { name = "Vermillion Pink", class = "metallic", hex = "#df5891" },
    [138] = { name = "Orange", class = "misc", hex = "#f6ae20" },
    [139] = { name = "Green", class = "misc", hex = "#b0ee6e" },
    [140] = { name = "Blue", class = "misc", hex = "#08e9fa" },
    [141] = { name = "Black Blue", class = "metallic", hex = "#0a0c17" },
    [142] = { name = "Black Purple", class = "metallic", hex = "#0c0d18" },
    [143] = { name = "Black Red", class = "metallic", hex = "#0e0d14" },
    [144] = { name = "Hunter Green", class = "misc", hex = "#9f9e8a" },
    [145] = { name = "Purple", class = "metallic", hex = "#621276" },
    [146] = { name = "V Dark Blue", class = "metallic", hex = "#0b1421" },
    [147] = { name = "Mod Shop Black", class = "misc", hex = "#11141a" },
    [148] = { name = "Purple", class = "matte", hex = "#6b1f7b" },
    [149] = { name = "Dark Purple", class = "matte", hex = "#1e1d22" },
    [150] = { name = "Lava Red", class = "metallic", hex = "#bc1917" },
    [151] = { name = "Forest Green", class = "matte", hex = "#2d362a" },
    [152] = { name = "Olive Drab", class = "matte", hex = "#696748" },
    [153] = { name = "Desert Brown", class = "matte", hex = "#7a6c55" },
    [154] = { name = "Desert Tan", class = "matte", hex = "#c3b492" },
    [155] = { name = "Foilage Green", class = "matte", hex = "#5a6352" },
    [156] = { name = "Alloy", class = "misc", hex = "#81827f" },
    [157] = { name = "Epsilon Blue", class = "misc", hex = "#afd6e4" },
    [158] = { name = "Pure Gold", class = "misc", hex = "#7a6440" },
    [159] = { name = "Brushed Gold", class = "misc", hex = "#7f6a48" },
    [161] = { name = "Anodized Red", class = "chameleon", hex = "#cf1020" },
    [162] = { name = "Anodized Wine", class = "chameleon", hex = "#5e1224" },
    [163] = { name = "Anodized Purple", class = "chameleon", hex = "#800080" },
    [164] = { name = "Anodized Blue", class = "chameleon", hex = "#0000ff" },
    [165] = { name = "Anodized Green", class = "chameleon", hex = "#008000" },
    [166] = { name = "Anodized Lime", class = "chameleon", hex = "#afff00" },
    [167] = { name = "Anodized Copper", class = "chameleon", hex = "#b87333" },
    [168] = { name = "Anodized Bronze", class = "chameleon", hex = "#cd7f32" },
    [169] = { name = "Anodized Champagne", class = "chameleon", hex = "#f7e7ce" },
    [170] = { name = "Anodized Gold", class = "chameleon", hex = "#ffd700" },
    [171] = { name = "Green Blue Flip", class = "chameleon", hex = "#1164b4" },
    [172] = { name = "Green Red Flip", class = "chameleon", hex = "#b43104" },
    [173] = { name = "Green Brown Flip", class = "chameleon", hex = "#735c12" },
    [174] = { name = "Green Turquoise Flip", class = "chameleon", hex = "#43c6db" },
    [175] = { name = "Green Purple Flip", class = "chameleon", hex = "#9d00ff" },
    [176] = { name = "Teal Purple Flip", class = "chameleon", hex = "#6a0dad" },
    [177] = { name = "Turquoise Red Flip", class = "chameleon", hex = "#e60026" },
    [178] = { name = "Turquoise Purple Flip", class = "chameleon", hex = "#30d5c8" },
    [179] = { name = "Cyan Purple Flip", class = "chameleon", hex = "#0ff0fc" },
    [180] = { name = "Blue Pink Flip", class = "chameleon", hex = "#4c2882" },
    [181] = { name = "Blue Green Flip", class = "chameleon", hex = "#138808" },
    [182] = { name = "Purple Red Flip", class = "chameleon", hex = "#9b111e" },
    [183] = { name = "Purple Green Flip", class = "chameleon", hex = "#6b2e53" },
    [184] = { name = "Magenta Green Flip", class = "chameleon", hex = "#ca1f7b" },
    [185] = { name = "Magenta Yellow Flip", class = "chameleon", hex = "#fedf00" },
    [186] = { name = "Burgundy Green Flip", class = "chameleon", hex = "#900020" },
    [187] = { name = "Magenta Cyan Flip", class = "chameleon", hex = "#00ffa1" },
    [188] = { name = "Copper Purple Flip", class = "chameleon", hex = "#b87333" },
    [189] = { name = "Magenta Orange Flip", class = "chameleon", hex = "#ff5f1f" },
    [190] = { name = "Red Orange Flip", class = "chameleon", hex = "#ff4500" },
    [191] = { name = "Orange Purple Flip", class = "chameleon", hex = "#b04080" },
    [192] = { name = "Orange Blue Flip", class = "chameleon", hex = "#0047ab" },
    [193] = { name = "White Purple Flip", class = "chameleon", hex = "#f8f0e3" },
    [194] = { name = "Red Rainbow Flip", class = "chameleon", hex = "#ed2939" },
    [195] = { name = "Blue Rainbow Flip", class = "chameleon", hex = "#4b0082" },
    [196] = { name = "Dark Green Pearl", class = "chameleon", hex = "#013220" },
    [197] = { name = "Dark Teal Pearl", class = "chameleon", hex = "#008080" },
    [198] = { name = "Dark Blue Pearl", class = "chameleon", hex = "#000080" },
    [199] = { name = "Dark Purple Pearl", class = "chameleon", hex = "#301934" },
    [200] = { name = "Oil Slick Pearl", class = "chameleon", hex = "#4b0082" },
    [201] = { name = "Light Green Pearl", class = "chameleon", hex = "#99e550" },
    [202] = { name = "Light Blue Pearl", class = "chameleon", hex = "#add8e6" },
    [203] = { name = "Light Pink Pearl", class = "chameleon", hex = "#ffb6c1" },
    [204] = { name = "Off White Pearl", class = "chameleon", hex = "#f2f0e6" },
    [205] = { name = "Pink Pearl", class = "chameleon", hex = "#eaadea" },
    [206] = { name = "Yellow Pearl", class = "chameleon", hex = "#fff000" },
    [207] = { name = "Green Pearl", class = "chameleon", hex = "#00a550" },
    [208] = { name = "Blue Pearl", class = "chameleon", hex = "#0000ff" },
    [209] = { name = "Cream Pearl", class = "chameleon", hex = "#fffdd0" },
    [210] = { name = "White Prismatic", class = "chameleon", hex = "#ffffff" },
    [211] = { name = "Graphite Prismatic", class = "chameleon", hex = "#251607" },
    [212] = { name = "Dark Blue Prismatic", class = "chameleon", hex = "#00008b" },
    [213] = { name = "Dark Purple Prismatic", class = "chameleon", hex = "#301934" },
    [214] = { name = "Hot Pink Prismatic", class = "chameleon", hex = "#ff69b4" },
    [215] = { name = "Dark Red Prismatic", class = "chameleon", hex = "#8b0000" },
    [216] = { name = "Dark Green Prismatic", class = "chameleon", hex = "#013220" },
    [217] = { name = "Black Prismatic", class = "chameleon", hex = "#000000" },
    [218] = { name = "Black Oil Spill", class = "chameleon", hex = "#121212" },
    [219] = { name = "Black Rainbow", class = "chameleon", hex = "#000000" },
    [220] = { name = "Prismatic", class = "chameleon", hex = "#cccccc" },
    [221] = { name = "Black Holographic", class = "chameleon", hex = "#101010" },
    [222] = { name = "White Holographic", class = "chameleon", hex = "#e6e8fa" },
    [223] = { name = "Anodized Monochrome", class = "chameleon", hex = "#000000", stops = { "#000000", "#080808", "#2b2b2b", "#676767", "#bcbcbc", "#1f1f1f" } },
    [224] = { name = "Day Night Flip", class = "chameleon", hex = "#18071a", stops = { "#18071a", "#2c0e47", "#0b01b8", "#523396", "#f4f30a", "#fd9103" } },
    [225] = { name = "Verlierer Flip", class = "chameleon", hex = "#9a0017", stops = { "#9a0017", "#98002b", "#830073", "#261b75", "#001d6c", "#200058" } },
    [226] = { name = "Anodized Sprunk", class = "chameleon", hex = "#147728", stops = { "#147728", "#147728", "#3a8b26", "#a6c526", "#cde036", "#6daf24" } },
    [227] = { name = "Vice City Flip", class = "chameleon", hex = "#db1c87", stops = { "#db1c87", "#da1f89", "#d42f91", "#8b54a6", "#7de2ef", "#517bbb" } },
    [228] = { name = "Synthwave Pearl", class = "chameleon", hex = "#000022", stops = { "#000022", "#141240", "#7b3e90", "#dc1785", "#d3574e", "#e0963b" } },
    [229] = { name = "Seasons Flip", class = "chameleon", hex = "#00d94e", stops = { "#00d94e", "#42dc49", "#e5ce3a", "#e57539", "#a9bdab", "#81f7f6" } },
    [230] = { name = "TBOGT Pearl", class = "chameleon", hex = "#c5b024", stops = { "#c5b024", "#c89a37", "#c93a78", "#913b9c", "#3287b8", "#2290b9" } },
    [231] = { name = "Bubblegum Pearl", class = "chameleon", hex = "#2a8eb4", stops = { "#2a8eb4", "#946a7b", "#a99093", "#a99194", "#946a7b", "#2b8fb4" } },
    [232] = { name = "Rainbow Prismatic", class = "chameleon", hex = "#6e0909", stops = { "#6e0909", "#57096e", "#09326e", "#096e2e", "#596e09", "#6e0a09" } },
    [233] = { name = "Sunset Flip", class = "chameleon", hex = "#994a00", stops = { "#994a00", "#965610", "#924502", "#2b0f2d", "#19073b", "#190635" } },
    [234] = { name = "Visions Prismatic", class = "chameleon", hex = "#ea7938", stops = { "#ea7938", "#ea7938", "#63c2bd", "#aaa767", "#beccaf", "#f2b722" } },
    [235] = { name = "Maziora Prismatic", class = "chameleon", hex = "#200a00", stops = { "#200a00", "#200a00", "#200a00", "#420a43", "#2a5d71", "#1b6b63" } },
    [236] = { name = "3DGlasses Flip", class = "chameleon", hex = "#f73030", stops = { "#f73030", "#f73030", "#ff3030", "#8d7071", "#00d6d6", "#00d5d5" } },
    [237] = { name = "Christmas Flip", class = "chameleon", hex = "#0a2a07", stops = { "#0a2a07", "#0a2a07", "#0a2b07", "#610f02", "#960000", "#960000" } },
    [238] = { name = "Temperature Prismatic", class = "chameleon", hex = "#ff0000", stops = { "#ff0000", "#ff0000", "#00fdff", "#4a00b5", "#ff8300", "#ffff00" } },
    [239] = { name = "HSW Flip", class = "chameleon", hex = "#e10019", stops = { "#e10019", "#d50011", "#e2481b", "#e3c71d", "#efed2f", "#e4e21f" } },
    [240] = { name = "Anodized Electro", class = "chameleon", hex = "#1c0029", stops = { "#1c0029", "#2b0f39", "#684b7a", "#a484b6", "#b998cb", "#7a5c8c" } },
    [241] = { name = "Monika Prismatic", class = "chameleon", hex = "#213730", stops = { "#213730", "#294f4a", "#37794f", "#70b637", "#98d348", "#37782a" } },
    [242] = { name = "Anodized Fubuki", class = "chameleon", hex = "#000000", stops = { "#000000", "#121d22", "#5e91aa", "#9adaf9", "#a9e8ff", "#72b0cc" } },
}

local CLASSES = {
    { id = "metallic", label = "Metallic" },
    { id = "matte", label = "Matte" },
    { id = "util", label = "Util" },
    { id = "worn", label = "Worn" },
    { id = "misc", label = "Misc" },
    { id = "chameleon", label = "Chameleon" },
}

local function measure()
    local model = joaat("adder")

    if not IsModelInCdimage(model) then return nil end

    RequestModel(model)

    local deadline = GetGameTimer() + 8000

    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then return nil end

        Wait(0)
    end

    local car = CreateVehicle(model, SAMPLE_SPOT.x, SAMPLE_SPOT.y, SAMPLE_SPOT.z, 0.0, false, false)

    SetModelAsNoLongerNeeded(model)

    if not (car and DoesEntityExist(car)) then return nil end

    SetEntityVisible(car, false, false)
    SetEntityCollision(car, false, false)
    FreezeEntityPosition(car, true)

    local out = {}

    for index = 0, CEILING do
        SetVehicleColours(car, index, index)

        Wait(0)

        local r, g, b = GetVehicleColor(car)
        local paint = PAINTS[index]

        if paint then
            if r ~= nil then
                out[#out + 1] = {
                    id    = index,
                    name  = paint.name,
                    class = paint.class,
                    hex   = paint.hex,
                    stops = paint.stops,
                }
            end
        elseif r ~= nil and not (r == 0 and g == 0 and b == 0) then
            out[#out + 1] = {
                id    = index,
                name  = ("Color %d"):format(index),
                class = "other",
                hex   = ("#%02x%02x%02x"):format(r % 256, g % 256, b % 256),
            }
        end
    end

    DeleteEntity(car)

    return out
end

RegisterNUICallback("vehicle_palette", function(_, cb)
    if palette then
        cb({ ok = true, classes = CLASSES, colors = palette })
        return
    end

    if sampling then
        local deadline = GetGameTimer() + 15000

        while sampling and GetGameTimer() < deadline do Wait(50) end

        cb({ ok = palette ~= nil, classes = CLASSES, colors = palette or {} })
        return
    end

    sampling = true

    local ok, result = pcall(measure)

    sampling = false

    if not ok or type(result) ~= "table" or #result == 0 then
        print(("[gg_lib] vehicle palette could not be measured: %s"):format(tostring(result)))

        cb({ ok = false, classes = CLASSES, colors = {} })
        return
    end

    palette = result

    cb({ ok = true, classes = CLASSES, colors = palette })
end)

AddEventHandler("onClientResourceStop", function(resource)
    if resource ~= RESOURCE then return end

    palette = nil
    sampling = false
end)
