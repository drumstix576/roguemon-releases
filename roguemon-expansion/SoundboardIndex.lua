local SoundboardIndex = { _form = nil }

local function closeForm(handle)
    if not handle then
        return
    end
    if ExternalUI and ExternalUI.BizForms and ExternalUI.BizForms.destroyForm then
        pcall(ExternalUI.BizForms.destroyForm, handle)
        return
    end
    pcall(forms.destroy, handle)
end

-- Static data: 45 category groups from gRoguemonMusicLists
local CATEGORIES = {
    { label = "Gym battle music", ids = {296, 689, 424, 520, 527, 595, 612} },
    { label = "Cycling music", ids = {282, 715, 441, 456, 547, 539, 607} },
    { label = "Indigo Plateau", ids = {295, 385, 395, 499} },
    { label = "Gym music", ids = {275, 654, 403, 484, 565, 606, 620, 608} },
    { label = "Forest music", ids = {287, 646, 386, 498, 576} },
    { label = "Lab music", ids = {301, 658, 485, 566} },
    { label = "Oak music", ids = {302, 486} },
    { label = "Pokecenter music", ids = {303, 335, 655, 401, 402, 482, 563} },
    { label = "Mart music", ids = {303, 656, 404, 483, 564} },
    { label = "Dungeon - Cave", ids = {288, 331, 334, 650, 388, 394, 398, 490, 496, 497, 494, 572, 575, 619} },
    { label = "Dungeon - Mnsn.", ids = {289, 387, 397, 491, 507, 573, 574} },
    { label = "Dungeon - Tower", ids = {306, 648, 358, 489, 493, 577, 605, 615} },
    { label = "Battle - Trainer", ids = {297, 695, 426, 429, 519, 522, 526, 592, 593, 594, 596} },
    { label = "Battle - Wild", ids = {298, 340, 341, 685, 423, 435, 518, 523, 525, 591, 611} },
    { label = "Battle - Boss", ids = {299, 688, 691, 692, 693, 425, 427, 428, 430, 431, 432, 433, 450, 451, 452, 521, 524, 528, 529, 531, 537, 597, 598, 599, 601, 600, 603, 613, 614, 625, 624, 623, 622} },
    { label = "Encounter - Boss", ids = {713, 410, 421, 422, 510, 602} },
    { label = "Enc. - Elite Four", ids = {710, 421, 438, 439, 604, 582} },
    { label = "Encounter - Rival", ids = {315, 687, 690, 434, 436, 437, 501, 533, 578, 621} },
    { label = "Enc. - Rival Exit", ids = {316, 502} },
    { label = "Route - group #1", ids = {291, 639, 643, 359, 363, 376, 380, 467, 477, 506, 535, 558} },
    { label = "Route - group #2", ids = {292, 640, 716, 360, 364, 377, 381, 393, 465, 469, 478, 534, 559, 616} },
    { label = "Route - group #3", ids = {293, 641, 642, 361, 365, 378, 382, 407, 466, 479, 481, 560} },
    { label = "Route - group #4", ids = {294, 642, 645, 362, 366, 379, 383, 384, 392, 468, 480, 488, 508, 561, 562} },
    { label = "City - Pewter", ids = {314, 678, 629, 349, 368, 373, 462, 464, 472, 474, 536, 542, 544} },
    { label = "City - Viridian", ids = {630, 352, 367, 463, 492, 551, 571} },
    { label = "City - Vermillion", ids = {313, 632, 350, 357, 370, 375, 461, 509, 546, 557, 567} },
    { label = "City - Celadon", ids = {309, 636, 351, 355, 372, 389, 446, 471, 550, 552, 554} },
    { label = "City - Fuchsia", ids = {308, 631, 353, 356, 371, 374, 470, 543, 548, 609} },
    { label = "Town - Lavender", ids = {280, 649, 453, 460, 473, 505, 545, 555} },
    { label = "Town - Pallet", ids = {300, 627, 628, 348, 354, 369, 448, 475, 541, 617} },
    { label = "City - Cinnabar", ids = {279, 336, 337, 635, 476, 553} },
    { label = "Safari Zone", ids = {264, 663, 455, 532} },
    { label = "Victory Road", ids = {295, 653, 399, 500, 569, 583, 570} },
    { label = "Title", ids = {278, 717, 443, 454, 538} },
    { label = "Surf music", ids = {305, 714, 440, 457, 540} },
    { label = "Ship music", ids = {304, 347, 659, 660, 504, 568} },
    { label = "Hideout music", ids = {274, 667, 396, 405, 447, 530, 618} },
    { label = "Game Corner", ids = {273, 657, 661, 445, 487, 390} },
    { label = "Silph music", ids = {307, 391, 495} },
    { label = "Encounter Girl", ids = {284, 697, 699, 700, 701, 409, 412, 417, 418, 420, 511, 515, 585, 586} },
    { label = "Encounter Boy", ids = {285, 686, 698, 703, 705, 408, 413, 414, 415, 419, 512, 516, 584, 587, 589} },
    { label = "Encounter Rocket", ids = {283, 704, 706, 708, 416, 411, 449, 503, 513, 514, 517, 579, 580, 581, 588, 590} },
    { label = "HOF", ids = {286, 721, 400, 442, 458} },
    { label = "Credits", ids = {290, 719, 444, 459} },
    { label = "City - Saffron", ids = {314, 637, 638, 372, 556, 549, 610} },
}

-- Static data: song title lookup for Soundboard button labels
local SONG_TITLES = {
    [264] = "RG: Evolution",
    [265] = "RS: Vs. Gym Leader",
    [266] = "RS: Vs. Trainer",
    [273] = "RG: Game Corner",
    [274] = "RG: Rocket Hideout",
    [275] = "RG: Gym",
    [278] = "RG: Title Screen",
    [279] = "RG: Cinnabar Island",
    [280] = "RG: Lavender Town",
    [282] = "RG: Cycling",
    [283] = "RG: Enc. - Rocket",
    [284] = "RG: Enc. - Girl",
    [285] = "RG: Enc. - Boy",
    [286] = "RG: HoF",
    [287] = "RG: Viridian Forest",
    [288] = "RG: Mt. Moon",
    [289] = "RG: Pokemon Mansion",
    [290] = "RG: Credits",
    [291] = "RG: Route 1",
    [292] = "RG: Route 24",
    [293] = "RG: Route 3",
    [294] = "RG: Route 11",
    [295] = "RG: Victory Road",
    [296] = "RG: Vs. Gym Leader",
    [297] = "RG: Vs. Trainer",
    [298] = "RG: Vs. Wild",
    [299] = "RG: Vs. Champion",
    [300] = "RG: Pallet Town",
    [301] = "RG: Oak's Lab",
    [302] = "RG: Professor Oak",
    [303] = "RG: Pokemon Center",
    [304] = "RG: S.S. Anne",
    [305] = "RG: Surf",
    [306] = "RG: Pokemon Tower",
    [307] = "RG: Silph Co.",
    [308] = "RG: Fuchsia City",
    [309] = "RG: Celadon City",
    [313] = "RG: Vermilion City",
    [314] = "RG: Pewter City",
    [315] = "RG: Enc. - Rival",
    [316] = "RG: Rival Exit",
    [331] = "RG: Sevii Cave",
    [334] = "RG: Sevii Dungeon",
    [335] = "RG: Sevii Islands 1-2-3",
    [336] = "RG: Sevii Islands 4-5",
    [337] = "RG: Sevii Islands 6-7",
    [340] = "RG: Vs. Mewtwo",
    [341] = "RG: Vs. Legendary",
    [347] = "RS: Abandoned Ship",
    [348] = "DP: Twinleaf Town (D)",
    [349] = "DP: Sandgem Town (D)",
    [350] = "DP: Solaceon Town (D)",
    [351] = "DP: Jubilife City (D)",
    [352] = "DP: Canalave City (D)",
    [353] = "DP: Oreburgh City (D)",
    [354] = "DP: Eterna City (D)",
    [355] = "DP: Hearthome City (D)",
    [356] = "DP: Veilstone City (D)",
    [357] = "DP: Sunyshore City (D)",
    [358] = "DP: Snowpoint City (D)",
    [359] = "DP: Route 201 (D)",
    [360] = "DP: Route 203 (D)",
    [361] = "DP: Route 205 (D)",
    [362] = "DP: Route 206 (D)",
    [363] = "DP: Route 209 (D)",
    [364] = "DP: Route 210 (D)",
    [365] = "DP: Route 216 (D)",
    [366] = "DP: Route 228 (D)",
    [367] = "DP: Twinleaf Town (N)",
    [368] = "DP: Sandgem Town (N)",
    [369] = "DP: Floaroma Town (N)",
    [370] = "DP: Solaceon Town (N)",
    [371] = "DP: Jubilife City (N)",
    [372] = "DP: Oreburgh City (N)",
    [373] = "DP: Hearthome City (N)",
    [374] = "DP: Veilstone City (N)",
    [375] = "DP: Sunyshore City (N)",
    [376] = "DP: Route 201 (N)",
    [377] = "DP: Route 203 (N)",
    [378] = "DP: Route 205 (N)",
    [379] = "DP: Route 206 (N)",
    [380] = "DP: Route 209 (N)",
    [381] = "DP: Route 210 (N)",
    [382] = "DP: Route 216 (N)",
    [383] = "DP: Route 228 (N)",
    [384] = "DP: The Underground",
    [385] = "DP: Victory Road",
    [386] = "DP: Eterna Forest",
    [387] = "DP: Old Chateau",
    [388] = "DP: Lake Caverns",
    [389] = "DP: Amity Square",
    [390] = "DP: Team Galactic HQ",
    [391] = "DP: Galactic Eterna Building",
    [392] = "DP: Great Marsh",
    [393] = "DP: Lake",
    [394] = "DP: Mt. Coronet",
    [395] = "DP: Spear Pillar",
    [396] = "DP: Stark Mountain",
    [397] = "DP: Oreburgh Gate",
    [398] = "DP: Oreburgh Mine",
    [399] = "DP: Vs. Pokemon League",
    [400] = "DP: Hall of Fame",
    [401] = "DP: Pokemon Center (D)",
    [402] = "DP: Pokemon Center (N)",
    [403] = "DP: Pokemon Gym",
    [404] = "DP: Poke Mart",
    [405] = "DP: Game Corner",
    [406] = "DP: Hall of Origin",
    [407] = "DP: GTS",
    [408] = "DP: Enc. - Youngster",
    [409] = "DP: Enc. - Twins",
    [410] = "DP: Enc. - Black Belt",
    [411] = "DP: Team Galactic Appears!",
    [412] = "DP: Enc. - Aroma Lady",
    [413] = "DP: Enc. - Hiker",
    [414] = "DP: Enc. - PI",
    [415] = "DP: Enc. - Sailor",
    [416] = "DP: Enc. - Collector",
    [417] = "DP: Enc. - Ace Trainer",
    [418] = "DP: Enc. - Lass",
    [419] = "DP: Enc. - Cyclist",
    [420] = "DP: Enc. - Artist",
    [421] = "DP: The Elite Four Appears!",
    [422] = "DP: Enc. - Cynthia",
    [423] = "DP: Vs. Wild Pokemon",
    [424] = "DP: Vs. Gym Leader",
    [425] = "DP: Vs. Uxie/Mesprit/Azelf",
    [426] = "DP: Vs. Trainer Battle",
    [427] = "DP: Vs. Galactic Boss",
    [428] = "DP: Vs. Champion",
    [429] = "DP: Vs. Team Galactic",
    [430] = "DP: Vs. Rival",
    [431] = "DP: Vs. Legendary",
    [432] = "DP: Vs. Galactic Cmdr.",
    [433] = "DP: Vs. Elite Four",
    [434] = "DP: Vs. Rival",
    [435] = "DP: Lake Surprise!",
    [436] = "DP: Lucas",
    [437] = "DP: Dawn",
    [438] = "DP: Legendary Appears!",
    [439] = "DP: Catastrophe!",
    [440] = "DP: Surf",
    [441] = "DP: Bicycle",
    [442] = "DP: HoF",
    [443] = "DP: Opening Movie",
    [444] = "DP: Ending Theme",
    [445] = "PL: Battle Arcade",
    [446] = "PL: Battle Hall",
    [447] = "PL: Battle Factory",
    [448] = "PL: Bossa Nova Lilycove",
    [449] = "PL: Looker's Theme",
    [450] = "PL: Vs. Giratina",
    [451] = "PL: Vs. Frontier Brain",
    [452] = "PL: Vs. Regi",
    [453] = "PL: Twinleaf Tune",
    [454] = "HG: Title Screen",
    [455] = "HG: Evolution",
    [456] = "HG: Bicycle",
    [457] = "HG: Surf",
    [458] = "HG: HoF",
    [459] = "HG: Ending Theme",
    [460] = "HG: New Bark Town",
    [461] = "HG: Cherrygrove City",
    [462] = "HG: Violet City",
    [463] = "HG: Azalea Town",
    [464] = "HG: Goldenrod City",
    [465] = "HG: Route 29",
    [466] = "HG: Route 30",
    [467] = "HG: Route 34",
    [468] = "HG: Route 38",
    [469] = "HG: Route 42",
    [470] = "HG: Vermilion City",
    [471] = "HG: Pewter City",
    [472] = "HG: Cerulean City",
    [473] = "HG: Lavender Town",
    [474] = "HG: Celadon City",
    [475] = "HG: Pallet Town",
    [476] = "HG: Cinnabar Island",
    [477] = "HG: Route 1",
    [478] = "HG: Route 3",
    [479] = "HG: Route 11",
    [480] = "HG: Route 24",
    [481] = "HG: Route 26",
    [482] = "HG: Pokemon Center",
    [483] = "HG: Poke Mart",
    [484] = "HG: Pokemon Gym",
    [485] = "HG: Elm Pokemon Lab",
    [486] = "HG: Professor Oak",
    [487] = "HG: Game Corner",
    [488] = "HG: Battle Tower",
    [489] = "HG: Sprout Tower",
    [490] = "HG: Union Cave",
    [491] = "HG: Ruins of Alph",
    [492] = "HG: National Park",
    [493] = "HG: Burned Tower",
    [494] = "HG: Olivine Lighthouse",
    [495] = "HG: Team Rocket HQ",
    [496] = "HG: Ice Path",
    [497] = "HG: Rock Tunnel",
    [498] = "HG: Viridian Forest",
    [499] = "HG: Victory Road",
    [500] = "HG: The Pokemon League",
    [501] = "HG: A Rival Appears!",
    [502] = "HG: A Rival Appears! (v2)",
    [503] = "HG: Radio Tower Occupied!",
    [504] = "HG: S.S. Aqua",
    [505] = "HG: Pokemon Lullaby",
    [506] = "HG: Pokemon March",
    [507] = "HG: Unown",
    [508] = "HG: Buena's Password",
    [509] = "HG: Eusine",
    [510] = "HG: Clair",
    [511] = "HG: Enc. - Girl",
    [512] = "HG: Enc. - Boy",
    [513] = "HG: Enc. - Suspicious",
    [514] = "HG: Enc. - Team Rocket",
    [515] = "HG: Enc. - Girl (v2)",
    [516] = "HG: Enc. - Boy (v2)",
    [517] = "HG: Enc. - Suspicious (v2)",
    [518] = "HG: Vs. Wild Pokemon",
    [519] = "HG: Vs. Trainer (J)",
    [520] = "HG: Vs. Gym Leader (J)",
    [521] = "HG: Vs. Rival",
    [522] = "HG: Vs. Team Rocket",
    [523] = "HG: Vs. Raikou",
    [524] = "HG: Vs. Champion",
    [525] = "HG: Vs. Wild Pokemon (K)",
    [526] = "HG: Vs. Trainer (K)",
    [527] = "HG: Vs. Gym Leader (K)",
    [528] = "HG: Vs. Lugia",
    [529] = "HG: Pokeathlon: Finals!",
    [530] = "HG: Battle Factory",
    [531] = "HG: Vs. Frontier Brain",
    [532] = "HG: Safari Zone",
    [533] = "HG: Ethan",
    [534] = "HG: Route 101",
    [535] = "HG: Route 201",
    [536] = "HG: Variety Channel",
    [537] = "HG: Vs. Super-Ancient PKMN",
    [538] = "BW: Intro 1",
    [539] = "BW: Cycling",
    [540] = "BW: Surf",
    [541] = "BW: Nuvema",
    [542] = "BW: Accumula",
    [543] = "BW: Anville",
    [544] = "BW: Lacunosa",
    [545] = "BW: Undella (Winter)",
    [546] = "BW: Undella (Summer)",
    [547] = "BW: Striaton",
    [548] = "BW: Nacrene",
    [549] = "BW: Castelia",
    [550] = "BW: Nimbasa",
    [551] = "BW: Driftveil",
    [552] = "BW: Mistralton",
    [553] = "BW: Icirrus",
    [554] = "BW: Opelucid (Black)",
    [555] = "BW: Opelucid (White)",
    [556] = "BW: Black City",
    [557] = "BW: White Forest",
    [558] = "BW: Route 1",
    [559] = "BW: Route 2 (Spring)",
    [560] = "BW: Route 4 (Spring)",
    [561] = "BW: Route 6 (Spring)",
    [562] = "BW: Skyarrow Bridge",
    [563] = "BW: Pokemon Center",
    [564] = "BW: Shopping Mall Nine",
    [565] = "BW: Gym",
    [566] = "BW: Juniper Lab",
    [567] = "BW: Gate",
    [568] = "BW: Royal Unova",
    [569] = "BW: Pokemon League",
    [570] = "BW: N's Castle",
    [571] = "BW: Dreamyard",
    [572] = "BW: Chargestone Cave",
    [573] = "BW: Cold Storage",
    [574] = "BW: Relic Castle",
    [575] = "BW: Dragonspiral Tower",
    [576] = "BW: Lostlorn Forest",
    [577] = "BW: Dragonspiral Tower Top",
    [578] = "BW: Cheren",
    [579] = "BW: Plasma",
    [580] = "BW: N",
    [581] = "BW: Plasma Plots",
    [582] = "BW: Ghetsis' Ambitions",
    [584] = "BW: Enc. - Boy",
    [585] = "BW: Enc. - Girl",
    [586] = "BW: Enc. - Twins",
    [587] = "BW: Enc. - Ace Trainer",
    [588] = "BW: Enc. - Suspicious",
    [589] = "BW: Enc. - Clerk",
    [590] = "BW: Enc. - Plasma",
    [591] = "BW: Vs. Wild",
    [592] = "BW: Vs. Wild Strong",
    [593] = "BW: Vs. Trainer",
    [594] = "BW: Vs. Subway Trainer",
    [595] = "BW: Vs. Gym Leader",
    [596] = "BW: Vs. Plasma",
    [597] = "BW: Vs. Elite Four",
    [598] = "BW: Vs. N",
    [599] = "BW: Vs. N Final",
    [600] = "BW: Vs. Ghetsis",
    [601] = "BW: Vs. Reshiram/Zekrom",
    [602] = "BW: Enc. - Cynthia",
    [603] = "BW: Vs. World Championships",
    [604] = "BW: N Legend Appears",
    [605] = "BW: N Room",
    [606] = "B2: Driftveil Gym",
    [607] = "B2: White Treehollow",
    [608] = "B2: Virbank Gym",
    [609] = "B2: Virbank",
    [610] = "B2: Humilau",
    [611] = "B2: Vs. Wild",
    [612] = "B2: Vs. Gym Leader",
    [613] = "B2: Vs. N",
    [614] = "B2: Vs. Regi",
    [615] = "B2: N Room",
    [616] = "B2: Route 22 (Spring)",
    [617] = "B2: Floccesy",
    [618] = "B2: Castelia Sewers",
    [619] = "B2: Cave of Being",
    [620] = "B2: Mistralton Gym",
    [621] = "B2: Rival",
    [622] = "B2: Vs. Champion (Kanto)",
    [623] = "B2: Vs. Champion (Sinnoh)",
    [624] = "B2: Vs. Neo Plasma",
    [625] = "B2: Vs. Ghetsis",
    [627] = "RS: Littleroot Town",
    [628] = "RS: Oldale Town",
    [629] = "RS: Petalburg City",
    [630] = "RS: Rustboro City",
    [631] = "RS: Dewford Town",
    [632] = "RS: Slateport City",
    [633] = "RS: Verdanturf Town",
    [634] = "RS: Fallarbor Town",
    [635] = "RS: Fortree City",
    [636] = "RS: Lilycove City",
    [637] = "RS: Sootopolis City",
    [638] = "RS: Ever Grande City",
    [639] = "RS: Route 101",
    [640] = "RS: Route 104",
    [641] = "RS: Route 110",
    [642] = "RS: Route 113",
    [643] = "RS: Route 119",
    [644] = "RS: Route 120",
    [645] = "RS: Route 122",
    [646] = "RS: Petalburg Woods",
    [647] = "RS: Mt. Chimney",
    [648] = "RS: Mt. Pyre",
    [649] = "RS: Mt. Pyre Exterior",
    [650] = "RS: Cave of Origin",
    [651] = "RS: Sealed Chamber",
    [652] = "RS: Underwater",
    [653] = "RS: Victory Road",
    [654] = "RS: Pokemon Gym",
    [655] = "RS: Pokemon Center",
    [656] = "RS: Poke Mart",
    [657] = "RS: Game Corner",
    [658] = "RS: Birch's Lab",
    [659] = "RS: Lilycove Museum",
    [660] = "RS: Oceanic Museum",
    [661] = "RS: Trick House",
    [662] = "RS: Hall of Fame Room",
    [663] = "RS: Safari Zone",
    [664] = "RS: Sailing",
    [665] = "RS: Contest",
    [666] = "RS: Contest Lobby",
    [667] = "RS: Aqua/Magma Hideout",
    [668] = "RS: Battle Frontier",
    [669] = "RS: Battle Arena",
    [670] = "RS: Battle Dome",
    [671] = "RS: Battle Dome Lobby",
    [672] = "RS: Battle Factory",
    [673] = "RS: Battle Palace",
    [674] = "RS: Battle Pike",
    [675] = "RS: Battle Pyramid",
    [676] = "RS: Battle Tower",
    [677] = "RS: Battle Tower (RS)",
    [678] = "RS: Pewter City (GSC)",
    -- Batch 2: Victory / Caught
    [679] = "RS: Caught!",
    [680] = "RS: Victory! (Wild)",
    [681] = "RS: Victory! (Gym Leader)",
    [682] = "RS: Victory! (League)",
    [683] = "RS: Victory! (Trainer)",
    [684] = "RS: Victory! (Aqua/Magma)",
    -- Batch 2: Battle
    [685] = "RS: Vs. Wild",
    [686] = "RS: Vs. Aqua/Magma",
    [687] = "RS: Vs. Champion",
    [688] = "RS: Vs. Regi",
    [689] = "RS: Vs. Kyogre/Groudon",
    [690] = "RS: Vs. Rival",
    [691] = "RS: Vs. Elite Four",
    [692] = "RS: Vs. Aqua/Magma Leader",
    [693] = "RS: Vs. Rayquaza",
    [694] = "RS: Vs. Frontier Brain",
    [695] = "RS: Vs. Mew",
    [696] = "RS: Intro Battle",
    -- Batch 2: Encounter
    [697] = "RS: Enc. - Girl",
    [698] = "RS: Enc. - Male",
    [699] = "RS: Enc. - Swimmer",
    [700] = "RS: Enc. - Female",
    [701] = "RS: Enc. - May",
    [702] = "RS: Enc. - Intense",
    [703] = "RS: Enc. - Cool",
    [704] = "RS: Enc. - Team Aqua",
    [705] = "RS: Enc. - Brendan",
    [706] = "RS: Enc. - Suspicious",
    [707] = "RS: Enc. - Rich",
    [708] = "RS: Enc. - Team Magma",
    [709] = "RS: Enc. - Twins",
    [710] = "RS: Enc. - Elite Four",
    [711] = "RS: Enc. - Hiker",
    [712] = "RS: Enc. - Interviewer",
    [713] = "RS: Enc. - Champion",
    -- Batch 2: Travel
    [714] = "RS: Surf",
    [715] = "RS: Cycling",
    [716] = "RS: Desert (Route 111)",
    -- Batch 2: Scene / Story
    [717] = "RS: Title Screen",
    [718] = "RS: Introduction",
    [719] = "RS: Credits",
    [720] = "RS: The End",
    [721] = "RS: Hall of Fame",
    [722] = "RS: Follow Me",
    [723] = "RS: Help",
    [724] = "RS: Cable Car",
    [725] = "RS: Rayquaza Appears",
    [726] = "RS: Awaken Legend (ME)",
    [727] = "RS: Abnormal Weather",
    [728] = "RS: Weather (Groudon)",
    -- Batch 2: Contest
    [729] = "RS: Contest Winner",
    [730] = "RS: Contest Results",
    [731] = "RS: Link Contest Pt. 1",
    [732] = "RS: Link Contest Pt. 2",
    [733] = "RS: Link Contest Pt. 3",
    [734] = "RS: Link Contest Pt. 4",
    [735] = "RS: Roulette",
    -- Batch 2: Battle Frontier
    [736] = "RS: Battle Pyramid Top",
    -- Batch 2: Fanfares / MEs
    [737] = "RS: Obtained B. Points (ME)",
    [738] = "RS: Match Call (ME)",
    [739] = "RS: Obtained Symbol (ME)",
    -- Batch 2: Unused / Test
    [740] = "RS: Littleroot (Test)",
    [741] = "RS: Route 38 (GSC)",
    [742] = "RS: Communication Center",
    [743] = "RS: vs. Legendary Beast",
}

-- Static data: 88 BW/B2W2 dropdown entries (IDs 538-625)
local BW_TRACKS = {
    "538 MUS_BW_INTRO_1",
    "539 MUS_BW_CYCLING",
    "540 MUS_BW_SURF",
    "541 MUS_BW_NUVEMA",
    "542 MUS_BW_ACCUMULA",
    "543 MUS_BW_ANVILLE",
    "544 MUS_BW_LACUNOSA",
    "545 MUS_BW_UNDELLA_WINTER",
    "546 MUS_BW_UNDELLA_SUMMER",
    "547 MUS_BW_STRIATON",
    "548 MUS_BW_NACRENE",
    "549 MUS_BW_CASTELIA",
    "550 MUS_BW_NIMBASA",
    "551 MUS_BW_DRIFTVEIL",
    "552 MUS_BW_MISTRALTON",
    "553 MUS_BW_ICIRRUS",
    "554 MUS_BW_OPELUCID_BLACK",
    "555 MUS_BW_OPELUCID_WHITE",
    "556 MUS_BW_BLACK_CITY",
    "557 MUS_BW_WHITE_FOREST",
    "558 MUS_BW_ROUTE1",
    "559 MUS_BW_ROUTE2_SPRING",
    "560 MUS_BW_ROUTE4_SPRING",
    "561 MUS_BW_ROUTE6_SPRING",
    "562 MUS_BW_SKYARROW_BRIDGE",
    "563 MUS_BW_POKE_CENTER",
    "564 MUS_BW_SHOPPING_MALL_NINE",
    "565 MUS_BW_GYM",
    "566 MUS_BW_JUNIPER_LAB",
    "567 MUS_BW_GATE",
    "568 MUS_BW_ROYAL_UNOVA",
    "569 MUS_BW_POKEMON_LEAGUE",
    "570 MUS_BW_N_CASTLE",
    "571 MUS_BW_DREAMYARD",
    "572 MUS_BW_CHARGESTONE_CAVE",
    "573 MUS_BW_COLD_STORAGE",
    "574 MUS_BW_RELIC_CASTLE",
    "575 MUS_BW_DRAGONSPIRAL_TOWER",
    "576 MUS_BW_LOSTLORN_FOREST",
    "577 MUS_BW_DRAGONSPIRAL_TOWER_TOP",
    "578 MUS_BW_CHEREN",
    "579 MUS_BW_PLASMA",
    "580 MUS_BW_N",
    "581 MUS_BW_PLASMA_PLOTS",
    "582 MUS_BW_GHETSIS",
    "584 MUS_BW_ENCOUNTER_BOY",
    "585 MUS_BW_ENCOUNTER_GIRL",
    "586 MUS_BW_ENCOUNTER_TWINS",
    "587 MUS_BW_ENCOUNTER_ACE_TRAINER",
    "588 MUS_BW_ENCOUNTER_SUSPICIOUS",
    "589 MUS_BW_ENCOUNTER_CLERK",
    "590 MUS_BW_ENCOUNTER_PLASMA",
    "591 MUS_BW_VS_WILD",
    "592 MUS_BW_VS_WILD_STRONG",
    "593 MUS_BW_VS_TRAINER *",
    "594 MUS_BW_VS_SUBWAY_TRAINER *",
    "595 MUS_BW_VS_GYM_LEADER *",
    "596 MUS_BW_VS_PLASMA *",
    "597 MUS_BW_VS_ELITE_FOUR",
    "598 MUS_BW_VS_N",
    "599 MUS_BW_VS_N_FINAL",
    "600 MUS_BW_VS_GHETSIS *",
    "601 MUS_BW_VS_RESHIRAM_ZEKROM",
    "602 MUS_BW_ENCOUNTER_CYNTHIA",
    "603 MUS_BW_VS_WORLD_CHAMPIONSHIPS *",
    "604 MUS_BW_N_LEGEND_APPEARS",
    "605 MUS_BW_N_ROOM",
    "606 MUS_B2_DRIFTVEIL_GYM *",
    "607 MUS_B2_WHITE_TREEHOLLOW",
    "608 MUS_B2_VIRBANK_GYM *",
    "609 MUS_B2_VIRBANK",
    "610 MUS_B2_HUMILAU",
    "611 MUS_B2_VS_WILD",
    "612 MUS_B2_VS_GYM_LEADER *",
    "613 MUS_B2_VS_N *",
    "614 MUS_B2_VS_REGI *",
    "615 MUS_B2_N_ROOM",
    "616 MUS_B2_ROUTE22_SPRING",
    "617 MUS_B2_FLOCCESY",
    "618 MUS_B2_CASTELIA_SEWERS *",
    "619 MUS_B2_CAVE_OF_BEING",
    "620 MUS_B2_MISTRALTON_GYM *",
    "621 MUS_B2_RIVAL *",
    "622 MUS_B2_VS_CHAMPION_KANTO *",
    "623 MUS_B2_VS_CHAMPION_SINNOH *",
    "624 MUS_B2_VS_NEO_PLASMA *",
    "625 MUS_B2_VS_GHETSIS *",

}

-- Static data: 117 RSE dropdown entries (IDs 627-743)
local RSE_TRACKS = {
    "627 MUS_RS_LITTLEROOT",
    "628 MUS_RS_OLDALE",
    "629 MUS_RS_PETALBURG",
    "630 MUS_RS_RUSTBORO",
    "631 MUS_RS_DEWFORD",
    "632 MUS_RS_SLATEPORT",
    "633 MUS_RS_VERDANTURF",
    "634 MUS_RS_FALLARBOR",
    "635 MUS_RS_FORTREE",
    "636 MUS_RS_LILYCOVE",
    "637 MUS_RS_SOOTOPOLIS",
    "638 MUS_RS_EVER_GRANDE",
    "639 MUS_RS_ROUTE101",
    "640 MUS_RS_ROUTE104",
    "641 MUS_RS_ROUTE110",
    "642 MUS_RS_ROUTE113",
    "643 MUS_RS_ROUTE119",
    "644 MUS_RS_ROUTE120",
    "645 MUS_RS_ROUTE122",
    "646 MUS_RS_PETALBURG_WOODS",
    "647 MUS_RS_MT_CHIMNEY",
    "648 MUS_RS_MT_PYRE",
    "649 MUS_RS_MT_PYRE_EXTERIOR",
    "650 MUS_RS_CAVE_OF_ORIGIN",
    "651 MUS_RS_SEALED_CHAMBER",
    "652 MUS_RS_UNDERWATER",
    "653 MUS_RS_VICTORY_ROAD",
    "654 MUS_RS_GYM",
    "655 MUS_RS_POKE_CENTER",
    "656 MUS_RS_POKE_MART",
    "657 MUS_RS_GAME_CORNER",
    "658 MUS_RS_BIRCH_LAB",
    "659 MUS_RS_LILYCOVE_MUSEUM",
    "660 MUS_RS_OCEANIC_MUSEUM",
    "661 MUS_RS_TRICK_HOUSE",
    "662 MUS_RS_HALL_OF_FAME_ROOM",
    "663 MUS_RS_SAFARI_ZONE",
    "664 MUS_RS_SAILING",
    "665 MUS_RS_CONTEST",
    "666 MUS_RS_CONTEST_LOBBY",
    "667 MUS_RS_AQUA_MAGMA_HIDEOUT",
    "668 MUS_RS_B_FRONTIER",
    "669 MUS_RS_B_ARENA",
    "670 MUS_RS_B_DOME",
    "671 MUS_RS_B_DOME_LOBBY",
    "672 MUS_RS_B_FACTORY",
    "673 MUS_RS_B_PALACE",
    "674 MUS_RS_B_PIKE",
    "675 MUS_RS_B_PYRAMID",
    "676 MUS_RS_B_TOWER",
    "677 MUS_RS_B_TOWER_RS",
    "678 MUS_RS_GSC_PEWTER",
    -- Batch 2: Victory / Caught
    "679 MUS_RS_CAUGHT",
    "680 MUS_RS_VICTORY_WILD",
    "681 MUS_RS_VICTORY_GYM_LEADER",
    "682 MUS_RS_VICTORY_LEAGUE",
    "683 MUS_RS_VICTORY_TRAINER",
    "684 MUS_RS_VICTORY_AQUA_MAGMA",
    -- Batch 2: Battle
    "685 MUS_RS_VS_WILD",
    "686 MUS_RS_VS_AQUA_MAGMA",
    "687 MUS_RS_VS_CHAMPION",
    "688 MUS_RS_VS_REGI",
    "689 MUS_RS_VS_KYOGRE_GROUDON",
    "690 MUS_RS_VS_RIVAL",
    "691 MUS_RS_VS_ELITE_FOUR",
    "692 MUS_RS_VS_AQUA_MAGMA_LEADER",
    "693 MUS_RS_VS_RAYQUAZA",
    "694 MUS_RS_VS_FRONTIER_BRAIN",
    "695 MUS_RS_VS_MEW",
    "696 MUS_RS_INTRO_BATTLE",
    -- Batch 2: Encounter
    "697 MUS_RS_ENCOUNTER_GIRL",
    "698 MUS_RS_ENCOUNTER_MALE",
    "699 MUS_RS_ENCOUNTER_SWIMMER",
    "700 MUS_RS_ENCOUNTER_FEMALE",
    "701 MUS_RS_ENCOUNTER_MAY",
    "702 MUS_RS_ENCOUNTER_INTENSE",
    "703 MUS_RS_ENCOUNTER_COOL",
    "704 MUS_RS_ENCOUNTER_AQUA",
    "705 MUS_RS_ENCOUNTER_BRENDAN",
    "706 MUS_RS_ENCOUNTER_SUSPICIOUS",
    "707 MUS_RS_ENCOUNTER_RICH",
    "708 MUS_RS_ENCOUNTER_MAGMA",
    "709 MUS_RS_ENCOUNTER_TWINS",
    "710 MUS_RS_ENCOUNTER_ELITE_FOUR",
    "711 MUS_RS_ENCOUNTER_HIKER",
    "712 MUS_RS_ENCOUNTER_INTERVIEWER",
    "713 MUS_RS_ENCOUNTER_CHAMPION",
    -- Batch 2: Travel
    "714 MUS_RS_SURF",
    "715 MUS_RS_CYCLING",
    "716 MUS_RS_DESERT",
    -- Batch 2: Scene / Story
    "717 MUS_RS_TITLE",
    "718 MUS_RS_INTRO",
    "719 MUS_RS_CREDITS",
    "720 MUS_RS_END",
    "721 MUS_RS_HALL_OF_FAME",
    "722 MUS_RS_FOLLOW_ME",
    "723 MUS_RS_HELP",
    "724 MUS_RS_CABLE_CAR",
    "725 MUS_RS_RAYQUAZA_APPEARS",
    "726 MUS_RS_AWAKEN_LEGEND",
    "727 MUS_RS_ABNORMAL_WEATHER",
    "728 MUS_RS_WEATHER_GROUDON",
    -- Batch 2: Contest
    "729 MUS_RS_CONTEST_WINNER",
    "730 MUS_RS_CONTEST_RESULTS",
    "731 MUS_RS_LINK_CONTEST_P1",
    "732 MUS_RS_LINK_CONTEST_P2",
    "733 MUS_RS_LINK_CONTEST_P3",
    "734 MUS_RS_LINK_CONTEST_P4",
    "735 MUS_RS_ROULETTE",
    -- Batch 2: Battle Frontier
    "736 MUS_RS_B_PYRAMID_TOP",
    -- Batch 2: Fanfares / MEs
    "737 MUS_RS_OBTAIN_B_POINTS",
    "738 MUS_RS_REGISTER_MATCH_CALL",
    "739 MUS_RS_OBTAIN_SYMBOL",
    -- Batch 2: Unused / Test
    "740 MUS_RS_LITTLEROOT_TEST",
    "741 MUS_RS_GSC_ROUTE38",
    "742 MUS_RS_C_COMM_CENTER",
    "743 MUS_RS_C_VS_LEGEND_BEAST",
}

-- Build ID -> label lookup from BW_TRACKS
local BW_TRACK_BY_ID = {}
for _, entry in ipairs(BW_TRACKS) do
    local id = tonumber(entry:match("^(%d+)"))
    if id then BW_TRACK_BY_ID[id] = entry end
end

-- Build ID -> label lookup from RSE_TRACKS
local RSE_TRACK_BY_ID = {}
for _, entry in ipairs(RSE_TRACKS) do
    local id = tonumber(entry:match("^(%d+)"))
    if id then RSE_TRACK_BY_ID[id] = entry end
end

-- BW/B2W2 track groups
local BW_GROUPS = {
    { label = "Title & Intro", ids = {538} },
    { label = "Overworld Travel", ids = {539, 540} },
    { label = "Cities & Towns", ids = {541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552, 553, 554, 555, 556, 557, 609, 610, 617, 618, 619} },
    { label = "Routes", ids = {558, 559, 560, 561, 562, 616} },
    { label = "Buildings", ids = {563, 564, 565, 566, 567, 568, 569, 570, 606, 607, 608, 615, 620} },
    { label = "Dungeons", ids = {571, 572, 573, 574, 575, 576, 577} },
    { label = "Encounters", ids = {578, 579, 580, 581, 582, 583, 584, 585, 586, 587, 588, 589, 590, 621} },
    { label = "Battles", ids = {591, 592, 593, 594, 595, 596, 597, 598, 599, 600, 601, 611, 612, 613, 614, 622, 623, 624, 625} },
    { label = "Misc", ids = {602, 603, 604, 605} },
}

local BW_GROUP_LABELS = {}
local BW_GROUP_BY_LABEL = {}
for i, g in ipairs(BW_GROUPS) do
    BW_GROUP_LABELS[i] = g.label
    BW_GROUP_BY_LABEL[g.label] = i
end

-- RSE track groups
local RSE_GROUPS = {
    { label = "Towns & Cities", ids = {627, 628, 629, 630, 631, 632, 633, 634, 635, 636, 637, 638} },
    { label = "Routes & Travel", ids = {639, 640, 641, 642, 643, 644, 645, 714, 715, 716} },
    { label = "Nature & Dungeons", ids = {646, 647, 648, 649, 650, 651, 652, 653} },
    { label = "Buildings", ids = {654, 655, 656, 657, 658, 659, 660, 661, 662, 663, 664} },
    { label = "Battles", ids = {685, 686, 687, 688, 689, 690, 691, 692, 693, 694, 695, 696} },
    { label = "Victory & Caught", ids = {679, 680, 681, 682, 683, 684} },
    { label = "Encounters", ids = {697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708, 709, 710, 711, 712, 713} },
    { label = "Scene & Story", ids = {717, 718, 719, 720, 721, 722, 723, 724, 725, 726, 727, 728} },
    { label = "Contests", ids = {665, 666, 729, 730, 731, 732, 733, 734, 735} },
    { label = "Battle Frontier", ids = {667, 668, 669, 670, 671, 672, 673, 674, 675, 676, 677, 736} },
    { label = "Fanfares & MEs", ids = {737, 738, 739} },
    { label = "Misc & Unused", ids = {678, 740, 741, 742, 743} },
}

local RSE_GROUP_LABELS = {}
local RSE_GROUP_BY_LABEL = {}
for i, g in ipairs(RSE_GROUPS) do
    RSE_GROUP_LABELS[i] = g.label
    RSE_GROUP_BY_LABEL[g.label] = i
end

local POLL_LABEL = "Roguemon:SoundboardIndexPoll"

local function buildTrackItems(groups, trackLookup, groupIndex)
    local items = {}
    local group = groups[groupIndex]
    if group then
        for _, id in ipairs(group.ids) do
            items[#items + 1] = trackLookup[id] or tostring(id)
        end
    end
    return items
end

function SoundboardIndex.show()
    closeForm(SoundboardIndex._form)
    SoundboardIndex._form = nil
    Program.removeFrameCounter(POLL_LABEL)

    local cols = 7
    local padding = 8
    local gap = 4
    local buttonW = 102
    local buttonH = 24
    local sectionGap = 12
    local rows = math.ceil(#CATEGORIES / cols)

    local gridW = cols * buttonW + (cols - 1) * gap
    local gridH = rows * buttonH + (rows - 1) * gap

    local bwRowH = 26
    local groupDdW = 120
    local playW = 50
    local trackDdW = gridW - groupDdW - playW - gap * 2

    local dropdownRows = 2
    local width = padding * 2 + gridW
    local height = padding + gridH + sectionGap + bwRowH * dropdownRows + gap * (dropdownRows - 1) + padding + 40

    local form = forms.newform(width, height, "Soundboard Index")
    SoundboardIndex._form = form
    forms.setproperty(form, "MinimizeBox", false)
    forms.setproperty(form, "MaximizeBox", false)

    -- Category buttons grid
    for i, cat in ipairs(CATEGORIES) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = padding + col * (buttonW + gap)
        local y = padding + row * (buttonH + gap)
        forms.button(form, cat.label, function()
            Roguemon.Soundboard.show(cat.ids, {
                title = cat.label,
                labelFn = function(id) return SONG_TITLES[id] or tostring(id) end,
            })
        end, x, y, buttonW, buttonH)
    end

    -- BW/B2W2 section: group dropdown + track dropdown + Play
    local bwY = padding + gridH + sectionGap
    local bwGroupDropdown = forms.dropdown(form, BW_GROUP_LABELS, padding, bwY, groupDdW, bwRowH)

    local trackX = padding + groupDdW + gap
    local bwTrackDropdown = forms.dropdown(form, buildTrackItems(BW_GROUPS, BW_TRACK_BY_ID, 1), trackX, bwY, trackDdW, bwRowH)
    forms.setproperty(bwTrackDropdown, "AutoCompleteSource", "ListItems")
    forms.setproperty(bwTrackDropdown, "AutoCompleteMode", "Append")

    local playX = trackX + trackDdW + gap
    forms.button(form, "Play", function()
        local text = forms.gettext(bwTrackDropdown)
        local id = tonumber(text:match("^(%d+)"))
        if id then
            Roguemon.Api.setMusic(id)
        end
    end, playX, bwY, playW, bwRowH)

    -- RSE section: group dropdown + track dropdown + Play
    local rseY = bwY + bwRowH + gap
    local rseGroupDropdown = forms.dropdown(form, RSE_GROUP_LABELS, padding, rseY, groupDdW, bwRowH)

    local rseTrackDropdown = forms.dropdown(form, buildTrackItems(RSE_GROUPS, RSE_TRACK_BY_ID, 1), trackX, rseY, trackDdW, bwRowH)
    forms.setproperty(rseTrackDropdown, "AutoCompleteSource", "ListItems")
    forms.setproperty(rseTrackDropdown, "AutoCompleteMode", "Append")

    forms.button(form, "Play", function()
        local text = forms.gettext(rseTrackDropdown)
        local id = tonumber(text:match("^(%d+)"))
        if id then
            Roguemon.Api.setMusic(id)
        end
    end, playX, rseY, playW, bwRowH)

    -- Poll group dropdowns for changes
    local prevBwGroup = BW_GROUP_LABELS[1]
    local prevRseGroup = RSE_GROUP_LABELS[1]
    Program.addFrameCounter(POLL_LABEL, 10, function()
        local ok = pcall(function()
            local currentBw = forms.gettext(bwGroupDropdown)
            if currentBw ~= prevBwGroup then
                prevBwGroup = currentBw
                local idx = BW_GROUP_BY_LABEL[currentBw]
                if idx then
                    forms.setdropdownitems(bwTrackDropdown, buildTrackItems(BW_GROUPS, BW_TRACK_BY_ID, idx), false)
                end
            end
            local currentRse = forms.gettext(rseGroupDropdown)
            if currentRse ~= prevRseGroup then
                prevRseGroup = currentRse
                local idx = RSE_GROUP_BY_LABEL[currentRse]
                if idx then
                    forms.setdropdownitems(rseTrackDropdown, buildTrackItems(RSE_GROUPS, RSE_TRACK_BY_ID, idx), false)
                end
            end
        end)
        if not ok then
            Program.removeFrameCounter(POLL_LABEL)
        end
    end)

    return form
end

function SoundboardIndex.close()
    closeForm(SoundboardIndex._form)
    SoundboardIndex._form = nil
end

return SoundboardIndex
