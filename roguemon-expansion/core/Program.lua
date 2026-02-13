local self = {}

-- Cache to avoid rebuilding pokemon objects when identity hasn't changed
local teamCache = {
    player = {},
    enemy = {},
}

local function buildMonKey(personality, trainerID)
    if personality == nil or trainerID == nil then
        return nil
    end
    return string.format("%08X:%08X", personality, trainerID)
end

function self.getNextLevelExp(pokemonID, level, experience)
    if not PokemonData.isValid(pokemonID) or level == nil or level >= 100 or experience == nil or GameSettings.gExperienceTables == nil then
        return 0, 100 -- arbitrary returned values to indicate this information isn't found and it's 0% of the way to next level
    end

    local growthRateIndex = Memory.readbyte(GameSettings.gSpeciesInfo + (pokemonID * GameSettings.sizeofBaseStatsPokemon) + GameSettings.offsetGrowthRate)
    -- sizeofExpTablePokemon is 404 - sizeofExpTableLevel * 101; 100 levels + lvl 0
    local expTableOffset = GameSettings.gExperienceTables + (growthRateIndex * Program.Addresses.sizeofExpTablePokemon) + (level * Program.Addresses.sizeofExpTableLevel)
    local expAtLv = Memory.readdword(expTableOffset)
    local expAtNextLv = Memory.readdword(expTableOffset + Program.Addresses.sizeofExpTableLevel)

    local currentExp = experience - expAtLv
    local totalExp = expAtNextLv - expAtLv

    return currentExp, totalExp
end

function self.updateMapLocation()
    -- Ensure route data is remapped before any map lookups
    if Roguemon and Roguemon.Core and Roguemon.Core.Utils then
        Roguemon.Core.Utils.remapRouteDataOffsets()
    end
    local newMapId = Memory.readword(GameSettings.gMapHeader + GameSettings.offsetMapHeaderLayoutId)
    Program.GameData.mapId = newMapId
end

function self.hasDefeatedTrainer(trainerId, saveBlock1Addr)
    if trainerId == nil or trainerId <= 0 then
        return false
    end
    if not Program.isValidMapLocation() then
        return false
    end
    saveBlock1Addr = saveBlock1Addr or Utils.getSaveBlock1Addr()
    local idAddrOffset = math.floor((Program.Addresses.offsetTrainerFlagStart + trainerId) / 8)
    local idBit = (Program.Addresses.offsetTrainerFlagStart + trainerId) % 8
    local trainerFlagAddr = saveBlock1Addr + GameSettings.gameFlagsOffset + idAddrOffset
    local result = Memory.readbyte(trainerFlagAddr)
    return Utils.getbits(result, idBit, 1) ~= 0
end

function self.changeGameSettingForLR(forced)
    -- set by default in Expansion ROM
    return
end

function self.readEncryptedSubstruct(dwordReader, buf, base, offset, magicword)
    return Utils.bit_xor(dwordReader(buf, base + offset), magicword),
           Utils.bit_xor(dwordReader(buf, base + offset + 4), magicword),
           Utils.bit_xor(dwordReader(buf, base + offset + 8), magicword)
end

function self.decodeNicknameFromBuf(buf, growth2, growth3, byteReader)
    local chars = {}
    local nicknameLen = GameSettings.sizeofPokemonNickname
    for i = 0, nicknameLen - 1 do
        local charByte = byteReader(buf, 8 + i)
        if charByte == Program.Addresses.nicknameCharEnd then break end
        chars[#chars + 1] = GameSettings.GameCharMap[charByte] or Constants.HIDDEN_INFO
    end

    -- Remaining two characters are stored in the growth substruct (nickname11/12).
    local extra1 = Utils.getbits(growth2, 21, 8)
    if extra1 ~= Program.Addresses.nicknameCharEnd and GameSettings.GameCharMap[extra1] then
        chars[#chars + 1] = GameSettings.GameCharMap[extra1]
    end
    local extra2 = Utils.getbits(growth3, 22, 8)
    if extra2 ~= Program.Addresses.nicknameCharEnd and GameSettings.GameCharMap[extra2] then
        chars[#chars + 1] = GameSettings.GameCharMap[extra2]
    end

    return Utils.formatSpecialCharacters(table.concat(chars))
end

function self.parseAttackSubstruct(attack01, attack23, attackPP)
    local moveIds = {
        Utils.getbits(attack01, 0, 11),
        Utils.getbits(attack01, 16, 11),
        Utils.getbits(attack23, 0, 11),
        Utils.getbits(attack23, 16, 11),
    }
    local movePPs = {
        Utils.getbits(attackPP, 0, 7),
        Utils.getbits(attackPP, 8, 7),
        Utils.getbits(attackPP, 16, 7),
        Utils.getbits(attackPP, 24, 7),
    }
    return moveIds, movePPs
end

function self.parseGrowthSubstruct(growth1, growth2, growth3)
    return {
        species = Utils.getbits(growth1, 0, 11),
        teraType = Utils.getbits(growth1, 11, 5),
        heldItem = Utils.getbits(growth1, 16, 10),
        experience = Utils.getbits(growth2, 0, 21),
        ppBonuses = Utils.getbits(growth3, 0, 8),
        friendship = Utils.getbits(growth3, 8, 8),
        pokeball = Utils.getbits(growth3, 16, 6),
        roguemonChosen = Utils.getbits(growth3, 30, 1),
    }
end

function self.parseMiscSubstruct(misc1, misc2, misc3)
    return {
        abilityNum = Utils.getbits(misc3, 29, 2),
        isEgg = Utils.getbits(misc2, 30, 1),
        gigantamaxFactor = Utils.getbits(misc2, 31, 1),
        hasPokerus = Utils.getbits(misc1, 0, 8) > 0,
    }
end

function self.parseStatusAndStats(buf, dwordReader)
    local status_aux = dwordReader(buf, GameSettings.offsetPokemonStatus)
    local sleep_turns_result = 0
    local status_result = 0
    if status_aux == 0 then
        status_result = 0
    elseif status_aux < 8 then
        sleep_turns_result = status_aux
        status_result = 1
    else
        for i = 2, 6 do
            if status_aux == (1 << (i + 1)) then
                status_result = i
            end
        end
    end

    local level_and_currenthp = dwordReader(buf, GameSettings.offsetPokemonStatsLvCurHp)
    local maxhp_and_atk = dwordReader(buf, GameSettings.offsetPokemonStatsMaxHpAtk)
    local def_and_speed = dwordReader(buf, GameSettings.offsetPokemonStatsDefSpe)
    local spatk_and_spdef = dwordReader(buf, GameSettings.offsetPokemonStatsSpaSpd)

    return {
        status = status_result,
        sleep_turns = sleep_turns_result,
        level = Utils.getbits(level_and_currenthp, 0, 8),
        curHP = Utils.getbits(level_and_currenthp, 16, 16),
        stats = {
            hp = Utils.getbits(maxhp_and_atk, 0, 16),
            atk = Utils.getbits(maxhp_and_atk, 16, 16),
            def = Utils.getbits(def_and_speed, 0, 16),
            spa = Utils.getbits(spatk_and_spdef, 0, 16),
            spd = Utils.getbits(spatk_and_spdef, 16, 16),
            spe = Utils.getbits(def_and_speed, 16, 16),
        }
    }
end

local function calculateMaxPP(moveId, ppBonuses, moveIndex)
    local moveData = MoveData.Moves[moveId] or {}
    local basePP = tonumber(moveData.pp) or 0
    if basePP == 0 then
        return 0
    end
    local bonus = Utils.getbits(ppBonuses or 0, (moveIndex - 1) * 2, 2)
    return basePP + math.floor((basePP * bonus) / 5)
end

local function refreshPokemonDynamicFields(pokemon, startAddress, personality, otid)
    if not pokemon or not startAddress or not personality or not otid then
        return
    end
    local substructStart = GameSettings.offsetPokemonSubstruct
    if not substructStart or not MiscData or not MiscData.TableData then
        return
    end

    local substructSize = GameSettings.sizeofPokemonSubstruct
    local aux = personality % 24 + 1
    local growthoffset = (MiscData.TableData.growth[aux] - 1) * substructSize
    local attackoffset = (MiscData.TableData.attack[aux] - 1) * substructSize
    local effortoffset = (MiscData.TableData.effort[aux] - 1) * substructSize
    local miscoffset = (MiscData.TableData.misc[aux] - 1) * substructSize
    local magicword = Utils.bit_xor(personality, otid)

    local function readEncrypted(offset)
        return Utils.bit_xor(Memory.readdword(startAddress + substructStart + offset), magicword)
    end

    local growth1 = readEncrypted(growthoffset)
    local growth2 = readEncrypted(growthoffset + 4)
    local growth3 = readEncrypted(growthoffset + 8)
    local effort1 = readEncrypted(effortoffset)
    local effort2 = readEncrypted(effortoffset + 4)
    local misc1 = readEncrypted(miscoffset)
    local misc2 = readEncrypted(miscoffset + 4)
    local misc3 = readEncrypted(miscoffset + 8)

    local attack01 = readEncrypted(attackoffset)
    local attack23 = readEncrypted(attackoffset + 4)
    local attackPP = readEncrypted(attackoffset + 8)

    local statusStats = self.parseStatusAndStats(nil, function(_, off)
        return Memory.readdword(startAddress + off)
    end)

    pokemon.pokemonID = Utils.getbits(growth1, 0, 11)
    pokemon.teraType = Utils.getbits(growth1, 11, 5)
    pokemon.heldItem = Utils.getbits(growth1, 16, 10)
    pokemon.experience = Utils.getbits(growth2, 0, 21)
    pokemon.friendship = Utils.getbits(growth3, 8, 8)
    pokemon.pokeball = Utils.getbits(growth3, 16, 6)
    pokemon.roguemonChosen = Utils.getbits(growth3, 30, 1)
    pokemon.ppBonuses = Utils.getbits(growth3, 0, 8)

    pokemon.status = statusStats.status
    pokemon.sleep_turns = statusStats.sleep_turns
    pokemon.level = statusStats.level
    pokemon.curHP = statusStats.curHP
    pokemon.stats = statusStats.stats

    pokemon.abilityNum = Utils.getbits(misc3, 29, 2)
    pokemon.isEgg = Utils.getbits(misc2, 30, 1)
    pokemon.gigantamaxFactor = Utils.getbits(misc2, 31, 1)
    pokemon.hasPokerus = Utils.getbits(misc1, 0, 8) > 0

    local moveIds, movePPs = self.parseAttackSubstruct(attack01, attack23, attackPP)
    pokemon.moves = pokemon.moves or {}
    for idx = 1, 4 do
        local moveId = moveIds[idx] or 0
        local move = pokemon.moves[idx] or {}
        local moveData = MoveData.Moves[moveId] or {}
        move.id = moveId
        move.level = move.level or 1
        move.name = moveData.name
        move.summary = moveData.summary
        if not Battle.inActiveBattle() and moveId ~= 0 then
            local maxPP = calculateMaxPP(moveId, pokemon.ppBonuses, idx)
            local currPP = movePPs[idx] or 0
            move.pp = math.min(currPP, maxPP)
        else
            move.pp = movePPs[idx] or 0
        end
        pokemon.moves[idx] = move
    end

    pokemon.evs = {
        hp = Utils.getbits(effort1, 0, 8),
        atk = Utils.getbits(effort1, 8, 8),
        def = Utils.getbits(effort1, 16, 8),
        spa = Utils.getbits(effort2, 0, 8),
        spd = Utils.getbits(effort2, 8, 8),
        spe = Utils.getbits(effort1, 24, 8),
    }
    pokemon.ivs = Utils.convertIVNumberToTable(misc2)
end

function self.readNewPokemon(startAddress, personality)
    local pkmnSize = GameSettings.sizeofPokemon
    local buf = Roguemon.Core.Utils.makeBuffer(startAddress, pkmnSize)

    local b, w, d, s = Roguemon.LoaderUtils.readers(buf)

    local otid = d(buf, 4)
    local magicword = Utils.bit_xor(personality, otid)

    local substructSize = GameSettings.sizeofPokemonSubstruct
    local substructStart = GameSettings.offsetPokemonSubstruct
    local aux = personality % 24 + 1
    local growthoffset = (MiscData.TableData.growth[aux] - 1) * substructSize
    local attackoffset = (MiscData.TableData.attack[aux] - 1) * substructSize
    local effortoffset = (MiscData.TableData.effort[aux] - 1) * substructSize
    local miscoffset = (MiscData.TableData.misc[aux] - 1) * substructSize
    local growth1, growth2, growth3 = self.readEncryptedSubstruct(d, buf, substructStart, growthoffset, magicword)
    local attack01, attack23, attackPP = self.readEncryptedSubstruct(d, buf, substructStart, attackoffset, magicword)
    local effort1, effort2 = self.readEncryptedSubstruct(d, buf, substructStart, effortoffset, magicword)
    local misc1, misc2, misc3 = self.readEncryptedSubstruct(d, buf, substructStart, miscoffset, magicword)

    local moveIds, movePPs = self.parseAttackSubstruct(attack01, attack23, attackPP)
    local growth = self.parseGrowthSubstruct(growth1, growth2, growth3)
    local misc = self.parseMiscSubstruct(misc1, misc2, misc3)
    local statusStats = self.parseStatusAndStats(buf, d)

    local trainerID = Utils.getbits(otid, 0, 16)
    local secretID = Utils.getbits(otid, 16, 16)
    local p1 = math.floor(personality / 65536)
    local p2 = personality % 65536
    local shinyValue = Utils.bit_xor(Utils.bit_xor(Utils.bit_xor(trainerID, secretID), p1), p2)
    local shinyModifier = Utils.getbits(w(buf, 0x1E), 14, 1)
    local isShiny = (shinyValue < Program.Values.ShinyOdds) ~= (shinyModifier == 1)

    local m1 = MoveData.Moves[moveIds[1]] or {}
    local m2 = MoveData.Moves[moveIds[2]] or {}
    local m3 = MoveData.Moves[moveIds[3]] or {}
    local m4 = MoveData.Moves[moveIds[4]] or {}

    return Program.DefaultPokemon:new({
        personality = personality,
        nickname = self.decodeNicknameFromBuf(buf, growth2, growth3, b),
        trainerID = trainerID,
        pokemonID = growth.species,
        heldItem = growth.heldItem,
        teraType = growth.teraType,
        pokeball = growth.pokeball,
        experience = growth.experience,
        friendship = growth.friendship,
        roguemonChosen = growth.roguemonChosen,
        ppBonuses = growth.ppBonuses,
        level = statusStats.level,
        gender = MiscData.getMonGender(growth.species, personality),
        nature = personality % 25,
        isEgg = misc.isEgg,
        gigantamaxFactor = misc.gigantamaxFactor,
        isShiny = isShiny,
        hasPokerus = misc.hasPokerus,
        abilityNum = misc.abilityNum,
        status = statusStats.status,
        sleep_turns = statusStats.sleep_turns,
        curHP = statusStats.curHP,
        stats = statusStats.stats,
        statStages = { hp = 6, atk = 6, def = 6, spa = 6, spd = 6, spe = 6, acc = 6, eva = 6 },
        moves = {
            { id = moveIds[1], level = 1, pp = (Battle.inActiveBattle() and movePPs[1] or math.min(movePPs[1] or 0, calculateMaxPP(moveIds[1], growth.ppBonuses, 1))), name = m1.name, summary = m1.summary },
            { id = moveIds[2], level = 1, pp = (Battle.inActiveBattle() and movePPs[2] or math.min(movePPs[2] or 0, calculateMaxPP(moveIds[2], growth.ppBonuses, 2))), name = m2.name, summary = m2.summary },
            { id = moveIds[3], level = 1, pp = (Battle.inActiveBattle() and movePPs[3] or math.min(movePPs[3] or 0, calculateMaxPP(moveIds[3], growth.ppBonuses, 3))), name = m3.name, summary = m3.summary },
            { id = moveIds[4], level = 1, pp = (Battle.inActiveBattle() and movePPs[4] or math.min(movePPs[4] or 0, calculateMaxPP(moveIds[4], growth.ppBonuses, 4))), name = m4.name, summary = m4.summary },
        },
        evs = {
            hp = Utils.getbits(effort1, 0, 8),
            atk = Utils.getbits(effort1, 8, 8),
            def = Utils.getbits(effort1, 16, 8),
            spa = Utils.getbits(effort2, 0, 8),
            spd = Utils.getbits(effort2, 8, 8),
            spe = Utils.getbits(effort1, 24, 8),
        },
        ivs = Utils.convertIVNumberToTable(misc2),
    })
end


function self.getPokemonTypes(isOwn, isLeft)
    local ownerAddressOffset = Utils.inlineIf(isOwn, 0, GameSettings.sizeofBattlePokemon)
    local leftAddressOffset = Utils.inlineIf(isLeft, 0, GameSettings.offsetBattlePokemonDoublesPartner) or 0
    local typesData = Memory.readword(GameSettings.gBattleMons + GameSettings.offsetBattlePokemonTypes + ownerAddressOffset + leftAddressOffset)
    return {
        PokemonData.TypeIndexMap[Utils.getbits(typesData, 0, 8)],
        PokemonData.TypeIndexMap[Utils.getbits(typesData, 8, 8)],
    }
end

function self.getMoveIdFromTMHMNumber(tmhmNumber, isHM)
    if isHM then
        tmhmNumber = tmhmNumber + 50
    end
    -- expansion struct is [ u16 tm_id, u16 move_id ]
    return Memory.readword(GameSettings.gTMHMItemMoveIds + (tmhmNumber * Program.Addresses.sizeofTMHMMoveId * 2) + 2)
end

function self.readTrainerGameData(trainerId)
    local trainer = Program.GameTrainer:new({
        trainerId = trainerId,
        defeated = Program.hasDefeatedTrainer(trainerId),
    })

    local trainerSize = GameSettings.sizeofTrainer
    local monSize = GameSettings.sizeofTrainerMon

    local startAddress = GameSettings.gTrainers + (trainerId * trainerSize)

    -- Gender: encounterMusic_gender low 7 bits music, bit7 gender
    local genderByte = Memory.readbyte(startAddress + 0x15)
    if Utils.getbits(genderByte, 7, 1) == 0 then
        trainer.gender = MiscData.Gender.MALE
    else
        trainer.gender = MiscData.Gender.FEMALE
    end

    trainer.trainerPic = Memory.readbyte(startAddress + 0x16)
    trainer.trainerBackPic = Memory.readbyte(startAddress + 0x2D)
    trainer.trainerClass = Memory.readbyte(startAddress + 0x14)

    -- Battle type is packed with startingStatus; battleType bit0-1, startingStatus bit2-7
    local battleByte = Memory.readbyte(startAddress + 0x24)
    trainer.doubleBattle = Utils.getbits(battleByte, 0, 2) == 1
    trainer.partyFlags = 3 -- items + custom moves always present in new struct

    trainer.items = {
        Memory.readword(startAddress + 0x0C),
        Memory.readword(startAddress + 0x0E),
        Memory.readword(startAddress + 0x10),
        Memory.readword(startAddress + 0x12),
    }

    -- Trainer name (fixed length)
    trainer.trainerName = Utils.readString(startAddress + 0x17)

    -- Class name lookup
    local classStartAddr = GameSettings.gTrainerClasses + (trainer.trainerClass * GameSettings.sizeofTrainerClass)
    trainer.trainerClass = Utils.readString(classStartAddr)

    -- Party pointer and size
    local partyPtr = Memory.readdword(startAddress + 0x08)
    trainer.partySize = Memory.readbyte(startAddress + 0x26)

    trainer.party = {}
    for i = 0, trainer.partySize - 1, 1 do
        local monOffset = partyPtr + (i * monSize)
        local packedIV = Memory.readdword(monOffset + 0x08)
        local ivValue = Utils.getbits(packedIV, 0, 5) -- use HP IV as representative (packed 5-bit fields)

        local monData = {
            pokemonID = Memory.readword(monOffset + 0x14),
            level = Memory.readbyte(monOffset + 0x1A),
            ivs = ivValue,
            heldItem = Memory.readword(monOffset + 0x16),
            moves = {
                Memory.readword(monOffset + 0x0C),
                Memory.readword(monOffset + 0x0E),
                Memory.readword(monOffset + 0x10),
                Memory.readword(monOffset + 0x12),
            },
        }
        table.insert(trainer.party, monData)
    end

    return trainer
end

function self.updatePokemonTeams()
    if not Tracker.Data.isNewGame and Program.GameData.PlayerTeam[1] == nil then
        Tracker.Data.isNewGame = true
    end

    local previousLeadMon = Program.GameData.PlayerTeam[1] or {}

    local addressOffset = 0
    for i = 1, 6, 1 do
        -- Lookup information on the player's Pokemon first
        local personality = Memory.readdword(GameSettings.pstats + addressOffset)
        local trainerID = Memory.readdword(GameSettings.pstats + addressOffset + 4)

        if personality ~= 0 or trainerID ~= 0 then
            local key = buildMonKey(personality, trainerID)
            if teamCache.player[i] ~= key or Program.GameData.PlayerTeam[i] == nil then
                local pokemon = Program.readNewPokemon(GameSettings.pstats + addressOffset, personality)
                if Program.validPokemonData(pokemon) then
                    Tracker.verifyDataForPlayer(pokemon.trainerID)

                    -- Include experience information for each Pokemon in the player's team
                    pokemon.currentExp, pokemon.totalExp = Program.getNextLevelExp(pokemon.pokemonID, pokemon.level, pokemon.experience)

                    Program.GameData.PlayerTeam[i] = pokemon
                    teamCache.player[i] = key
                end
            elseif Program.GameData.PlayerTeam[i] ~= nil then
                local pokemon = Program.GameData.PlayerTeam[i]
                refreshPokemonDynamicFields(pokemon, GameSettings.pstats + addressOffset, personality, trainerID)
                pokemon.currentExp, pokemon.totalExp = Program.getNextLevelExp(pokemon.pokemonID, pokemon.level, pokemon.experience)
            end
        else
            Program.GameData.PlayerTeam[i] = nil
            teamCache.player[i] = nil
        end

        -- Then lookup information on the opposing Pokemon
        personality = Memory.readdword(GameSettings.estats + addressOffset)
        trainerID = Memory.readdword(GameSettings.estats + addressOffset + 4)

        if personality ~= 0 or trainerID ~= 0 then
            local key = buildMonKey(personality, trainerID)
            if teamCache.enemy[i] ~= key or Program.GameData.EnemyTeam[i] == nil then
                local pokemon = Program.readNewPokemon(GameSettings.estats + addressOffset, personality)
                if Program.validPokemonData(pokemon) then
                    -- Double-check a race condition where current PP values are wildly out of range if retrieved right before a battle begins
                    if not Battle.inActiveBattle() then
                        for _, move in pairs(pokemon.moves) do
                            if move.id ~= 0 then
                                move.pp = tonumber(MoveData.Moves[move.id].pp) -- set value to max PP
                            end
                        end
                    end

                    Program.GameData.EnemyTeam[i] = pokemon
                    teamCache.enemy[i] = key
                end
            elseif Program.GameData.EnemyTeam[i] ~= nil then
                local pokemon = Program.GameData.EnemyTeam[i]
                refreshPokemonDynamicFields(pokemon, GameSettings.estats + addressOffset, personality, trainerID)
            end
        else
            Program.GameData.EnemyTeam[i] = nil
            teamCache.enemy[i] = nil
        end

        -- Next Pokemon - Each is offset by 100 bytes
        addressOffset = addressOffset + GameSettings.sizeofPokemon
    end

    -- If the lead Pokémon changed (new mon viewed), then try to turn it into a GachaMon; only for catches, exclude battles
    local currentLeadMon = Program.GameData.PlayerTeam[1]
    if currentLeadMon and not Battle.inActiveBattle() then
        GachaMonData.tryAddToRecentMons(currentLeadMon)
    end
end

function self.isInEvolutionScene()
    local evoInfo = GameSettings.sEvoStruct
    local taskID = Memory.readbyte(evoInfo + Program.Addresses.offsetEvoInfoTaskId)

    -- only 16 tasks possible max in gTasks
    if taskID > 15 then return false end

    -- Check for Evolution Task (Task_EvolutionScene + 1)
    local taskFunc = Memory.readdword(GameSettings.gTasks + (Program.Addresses.sizeofTaskStruct * taskID))
    if taskFunc ~= GameSettings.Task_EvolutionScene then return false end

    -- Check if the Task is active
    local isActive = Memory.readbyte(GameSettings.gTasks + (Program.Addresses.sizeofTaskStruct * taskID) + Program.Addresses.offsetTaskIsActive)
    return isActive == 1
end

return self
