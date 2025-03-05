--
-- Please see the license.txt file included with this distribution for
-- attribution and copyright information.
--
-- luacheck: globals Pets CombatManagerKw
-- luacheck: globals showTurnMessage centerOnToken onNPCPostAdd onVehiclePostAdd
-- luacheck: globals trySetCohortLinkAndFaction addUnit
-- luacheck: globals updatePetOwner customOnRecordTypeEvent setOwnership
local showTurnMessageOriginal;
local centerOnTokenOriginal;
local onNPCPostAddOriginal;
local onVehiclePostAddOriginal;
local addUnitOriginal;
local fOnRecordTypeEvent;

function onInit()
    showTurnMessageOriginal = CombatManager.showTurnMessage;
    CombatManager.showTurnMessage = showTurnMessage;

    centerOnTokenOriginal = CombatManager.centerOnToken;
    CombatManager.centerOnToken = centerOnToken;

    onNPCPostAddOriginal = CombatRecordManager.getRecordTypePostAddCallback('npc');
    CombatRecordManager.setRecordTypePostAddCallback('npc', onNPCPostAdd);

    onVehiclePostAddOriginal = CombatRecordManager.getRecordTypePostAddCallback('vehicle');
    CombatRecordManager.setRecordTypePostAddCallback('vehicle', onVehiclePostAdd);

    if Session.IsHost then
        DB.addHandler('charsheet.*', 'onObserverUpdate', updatePetOwner);

        --Adds ability for players to tic reaction box in CT
        fOnRecordTypeEvent = CombatRecordManager.onRecordTypeEvent;
        CombatRecordManager.onRecordTypeEvent = customOnRecordTypeEvent;
    end

    if CombatManagerKw then
        addUnitOriginal = CombatManagerKw.addUnit;
        CombatManagerKw.addUnit = addUnit;
    end
end

function onTabletopInit()
    if Session.IsHost then
        setOwnership();
    end
end

function showTurnMessage(nodeEntry, bActivate, bSkipBell)
    showTurnMessageOriginal(nodeEntry, bActivate, bSkipBell);

    local sClass, sRecord = DB.getValue(nodeEntry, 'link', '', '');
    local bHidden = CombatManager.isCTHidden(nodeEntry);
    if not bHidden and (sClass ~= 'charsheet') then -- Allow non-character sheet turns as well for the sake of cohorts.
        if bActivate and not bSkipBell and OptionsManager.isOption('RING', 'on') then
            if sRecord ~= '' then
                local nodeCohort = DB.findNode(sRecord);
                if nodeCohort then
                    local sOwner = nodeCohort.getOwner();
                    if sOwner then
                        User.ringBell(sOwner);
                    end
                end
            end
        end
    end
end

function centerOnToken(nodeEntry, bOpen)
    local bReturn = centerOnTokenOriginal(nodeEntry, bOpen);

    if not Session.IsHost and Pets.isCohort(nodeEntry) and DB.isOwner(ActorManager.getCreatureNode(nodeEntry)) then
        bReturn = ImageManager.centerOnToken(CombatManager.getTokenFromCT(nodeEntry), bOpen);
    end
    return bReturn
end

function onNPCPostAdd(tCustom)
    onNPCPostAddOriginal(tCustom);
    trySetCohortLinkAndFaction(tCustom);
end

function onVehiclePostAdd(tCustom)
    onVehiclePostAddOriginal(tCustom);
    trySetCohortLinkAndFaction(tCustom);
end

function addUnit(tCustom)
    addUnitOriginal(tCustom);
    trySetCohortLinkAndFaction(tCustom);
end

function trySetCohortLinkAndFaction(tCustom)
    local bIsCohort = Pets.isCohort(tCustom.nodeRecord);
    if tCustom.nodeCT and bIsCohort then
        local sClass = tCustom.sClass or LibraryData.getRecordDisplayClass(tCustom.sRecordType);
        local nodeCommander = Pets.getCommanderNode(tCustom.nodeRecord);
        local sFaction = ActorManager.getFaction(nodeCommander);
        local sOwner = DB.getOwner(nodeCommander);
        local nodeRct = DB.createChild(tCustom.nodeCT, 'reaction', 'number');
        DB.setOwner(nodeRct, sOwner);
        DB.setOwner(DB.getChild(tCustom.nodeCT, 'spellslots'), sOwner);
        DB.setValue(tCustom.nodeCT, 'link', 'windowreference', sClass, tCustom.nodeRecord.getPath());
        DB.setValue(tCustom.nodeCT, 'friendfoe', 'string', sFaction);
    end
end

function updatePetOwner(node)
    --updates PC's ability to tic reaction box
    local nodeCT = ActorManager.getCTNode(node);
    if not nodeCT then
        return;
    end

    local sOwner = DB.getOwner(node);
    local bOwnerCleared;
    if not sOwner or sOwner == '' then
        bOwnerCleared = true;
    end
    if not bOwnerCleared then
        local nodeRct = DB.createChild(nodeCT, 'reaction', 'number');
        DB.setOwner(nodeRct, sOwner);
    else
        DB.removeAllHolders(DB.getChild(nodeCT, 'reaction'));
    end

    --updates player's ability to tic reaction box & use spell slots for their pets
    if DB.getChildCount(node, 'cohorts') < 1 then
        return;
    end
    for _,nodeCTLoop in ipairs(CombatManager.getAllCombatantNodes()) do
        if Pets.isCohort(nodeCTLoop) and Pets.getCommanderNode(nodeCTLoop) == node then
            if bOwnerCleared then
                DB.removeAllHolders(DB.getChild(nodeCTLoop, 'reaction'));
                DB.removeAllHolders(DB.getChild(nodeCTLoop, 'spellslots'));
            else
                local nodeRct = DB.createChild(nodeCTLoop, 'reaction', 'number');
                DB.setOwner(nodeRct, sOwner);
                DB.setOwner(DB.getChild(nodeCTLoop, 'spellslots'), sOwner);
            end
        end
    end
end

--Adds ability for players to tic reaction box in CT
function customOnRecordTypeEvent(sRecordType, tCustom)
    local bResult = fOnRecordTypeEvent(sRecordType, tCustom);

    if Session.IsHost then
        if not tCustom.nodeRecord then
            tCustom.nodeRecord = DB.findNode(tCustom.sRecord);
        end
        if ActorManager.isPC(tCustom.nodeRecord) then
            local sOwner = DB.getOwner(tCustom.nodeRecord);
            if sOwner and sOwner ~= '' then
                local nodeCT = ActorManager.getCTNode(tCustom.nodeRecord);
                local nodeRct = DB.createChild(nodeCT, 'reaction', 'number');
                DB.setOwner(nodeRct, sOwner);
            end
        end
    end

    return bResult;
end

function setOwnership()
    for _,nodeCT in ipairs(CombatManager.getAllCombatantNodes()) do
        if ActorManager.isPC(nodeCT) then
            local nodeChar = ActorManager.getCreatureNode(nodeCT);
            local sOwner = DB.getOwner(nodeChar);
            if sOwner and sOwner ~= '' then
                local nodeRct = DB.createChild(nodeCT, 'reaction', 'number');
                DB.setOwner(nodeRct, sOwner);
            end
        elseif Pets.isCohort(nodeCT) then
            local nodeCommander = Pets.getCommanderNode(nodeCT);
            local sOwner = DB.getOwner(nodeCommander);
            if sOwner and sOwner ~= '' then
                local nodeRct = DB.createChild(nodeCT, 'reaction', 'number');
                DB.setOwner(nodeRct, sOwner);
                DB.setOwner(DB.getChild(nodeCT, 'spellslots'), sOwner);
            end
        end
    end
end