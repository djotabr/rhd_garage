local VehicleShow = nil

local Utils = lib.load('modules.utils')
local Deformation = lib.load('modules.deformation')

local function spawnvehicle ( data )
    lib.requestModel(data.model)
    local serverData = lib.callback.await("rhd_garage:cb_server:createVehicle", false, {
        model = data.model,
        plate = data.plate,
        coords = data.coords,
        vehtype = Utils.getVehicleTypeByModel(data.model)
    })

    if serverData.netId < 1 then
        return
    end

    while not NetworkDoesEntityExistWithNetworkId(serverData.netId) do Wait(10) end
    local veh = NetworkGetEntityFromNetworkId(serverData.netId)
    
    while Utils.getPlate(veh) ~= serverData.plate do
        SetVehicleNumberPlateText(veh, serverData.plate) Wait(10)
    end

    SetVehicleOnGroundProperly(veh)
    if Config.SpawnInVehicle then
        TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    end

    SetVehicleEngineHealth(veh, data.engine + 0.0)
    SetVehicleBodyHealth(veh, data.body + 0.0)
    Utils.setFuel(veh, data.fuel)
    Deformation.set(veh, serverData.deformation)

    TriggerServerEvent("rhd_garage:server:updateState", {
        vehicle = veh,
        prop = serverData.props,
        plate = serverData.plate,
        state = 0,
        garage = data.garage,
        deformation = serverData.deformation
    })
    
    Entity(veh).state:set('vehlabel', data.vehicle_name)
    TriggerEvent("vehiclekeys:client:SetOwner", serverData.plate:trim())
end

local function actionMenu ( data )
    local actionData = {
        id = 'garage_action',
        title = data.vehName:upper(),
        menu = 'garage_menu',
        onBack = function ()
            if DoesEntityExist(VehicleShow) then
                DeleteVehicle(VehicleShow)
                VehicleShow = nil
            end
        end,
        onExit = function ()
            if DoesEntityExist(VehicleShow) then
                DeleteVehicle(VehicleShow)
                VehicleShow = nil
            end
        end,
        options = {
            {
                title = data.impound and locale('rhd_garage:pay_impound') or locale('rhd_garage:take_out_veh'),
                icon = data.impound and 'hand-holding-dollar' or 'sign-out-alt',
                iconAnimation = Config.IconAnimation,
                onSelect = function ()
                    if DoesEntityExist(VehicleShow) then
                        DeleteVehicle(VehicleShow)
                        VehicleShow = nil
                    end

                    if data.impound then
                        Utils.createMenu({
                            id = 'pay_methode',
                            title = locale('rhd_garage:pay_methode'):upper(),
                            options = {
                                {
                                    title = locale('rhd_garage:pay_methode_cash'):upper(),
                                    icon = 'dollar-sign',
                                    description = locale('rhd_garage:pay_with_cash'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function ()  
                                        if fw.gm('cash') < data.depotprice then return Utils.notify(locale('rhd_garage:not_enough_cash'), 'error') end
                                        local success = lib.callback.await('rhd_garage:cb_server:removeMoney', false, 'cash', data.depotprice)
                                        if success then
                                            Utils.notify(locale('rhd_garage:success_pay_impound'), 'success')
                                            return spawnvehicle( data )
                                        end
                                    end
                                },
                                {
                                    title = locale('rhd_garage:pay_methode_bank'):upper(),
                                    icon = 'fab fa-cc-mastercard',
                                    description = locale('rhd_garage:pay_with_bank'),
                                    iconAnimation = Config.IconAnimation,
                                    onSelect = function ()  
                                        if fw.gm('bank') < data.depotprice then return Utils.notify(locale('rhd_garage:not_enough_bank'), 'error') end
                                        local success = lib.callback.await('rhd_garage:cb_server:removeMoney', false, 'bank', data.depotprice)
                                        if success then
                                            Utils.notify(locale('rhd_garage:success_pay_impound'), 'success')
                                            return spawnvehicle( data )
                                        end
                                    end
                                }
                            }
                        })
                        return
                    end

                    spawnvehicle( data )
                end
            },
            
        }
    }
    
    if not data.impound then
        if Config.TransferVehicle.enable then
            actionData.options[#actionData.options+1] = {
                title = locale("rhd_garage:transferveh_title"),
                icon = "exchange-alt",
                iconAnimation = Config.IconAnimation,
                metadata = {
                    price = lib.math.groupdigits(Config.TransferVehicle.price, '.')
                },
                onSelect = function ()
                    DeleteVehicle(VehicleShow)
                    VehicleShow = nil

                    local transferInput = lib.inputDialog(data.vehName:upper(), {
                        { type = 'number', label = 'Player Id', required = true },
                    })
                    
                    if transferInput then
                        local clData = {
                            targetSrc = transferInput[1],
                            plate = data.plate,
                            price = Config.TransferVehicle.price,
                            garage = data.garage
                        }
                        lib.callback('rhd_garage:cb_server:transferVehicle', false, function (success, information)
                            if not success then return
                                Utils.notify(information, "error")
                            end

                            Utils.notify(information, "success")
                        end, clData)
                    end
                end
            }
        end

        if Config.SwapGarage.enable then
            actionData.options[#actionData.options+1] = {
                title = locale('rhd_garage:swapgarage_title'),
                icon = "retweet",
                iconAnimation = Config.IconAnimation,
                metadata = {
                    price = lib.math.groupdigits(Config.SwapGarage.price, '.')
                },
                onSelect = function ()
                    DeleteVehicle(VehicleShow)
                    VehicleShow = nil

                    local garageTable = function ()
                        local result = {}
                        for k, v in pairs(GarageZone) do
                            if k ~= data.garage and not v.impound then
                                result[#result+1] = { value = k }
                            end
                        end
                        return result
                    end

                    local garageInput = lib.inputDialog(data.garage:upper(), {
                        { type = 'select', label = locale('rhd_garage:swapgarage_input_label'), options = garageTable(), required = true},
                    })

                    if garageInput then
                        local vehdata = {
                            plate = data.plate,
                            newgarage = garageInput[1]
                        }

                        if fw.gm('cash') < Config.SwapGarage.price then return Utils.notify(locale("rhd_garage:swapgarage_need_money", lib.math.groupdigits(Config.SwapGarage.price, '.')), 'error') end
                        local success = lib.callback.await('rhd_garage:cb_server:removeMoney', false, 'cash', Config.SwapGarage.price)
                        if not success then return end

                        lib.callback('rhd_garage:cb_server:swapGarage', false, function (success)
                            if not success then return
                                Utils.notify(locale("rhd_garage:swapgarage_error"), "error")
                            end
    
                            Utils.notify(locale('rhd_garage:swapgarage_success', vehdata.newgarage), "success")
                        end, vehdata)
                    end
                end
            }
        end

        actionData.options[#actionData.options+1] = {
            title = locale('rhd_garage:change_veh_name'),
            icon = 'pencil',
            iconAnimation = Config.IconAnimation,
            metadata = {
                price = lib.math.groupdigits(Config.SwapGarage.price, '.')
            },
            onSelect = function ()
                DeleteVehicle(VehicleShow)
                VehicleShow = nil
                
                local input = lib.inputDialog(data.vehName, {
                    { type = 'input', label = '', placeholder = locale('rhd_garage:change_veh_name_input'), required = true, max = 20 },
                })
                
                if input then
                    if fw.gm('cash') < Config.changeNamePrice then return Utils.notify(locale('rhd_garage:change_veh_name_nocash'), 'error') end

                    local success = lib.callback.await('rhd_garage:cb_server:removeMoney', false, 'cash', Config.changeNamePrice)
                    if success then
                        CNV[data.plate] = {
                            name = input[1]
                        }
    
                        TriggerServerEvent('rhd_garage:server:saveCustomVehicleName', CNV)
                    end
                end
            end
        }
    end

    Utils.createMenu(actionData)
end


local function openMenu ( data )
    if not data then return end
    data.type = data.type or "car"
    
    local menuData = {
        id = 'garage_menu',
        title = data.garage:upper(),
        options = {}
    }

    local vehData = lib.callback.await('rhd_garage:cb_server:getVehicleList', false, data.garage, data.impound, data.shared)
    
    if not vehData then
        return    
    end

    for i=1, #vehData do
        local vd = vehData[i]
        local vehProp = vd.vehicle
        local vehModel = vd.model
        local plate = vd.plate
        local vehDeformation = vd.deformation
        local gState = vd.state
        local pName = vd.owner or "Unkown Players"
        local fakeplate = vd.fakeplate
        local engine = vd.engine
        local body = vd.body
        local fuel = vd.fuel
        local dp = vd.depotprice

        local vehName = vd.vehicle_name or fw.gvn( vehModel )
        local customvehName = CNV[plate:trim()] and CNV[plate:trim()].name
        local vehlabel = customvehName or vehName

        local shared_garage = data.shared
        local disabled = false
        local description = ''

        plate = fakeplate and fakeplate:trim() or plate:trim()

        local vehicleClass = GetVehicleClassFromName(vehModel)
        local vehicleType = Utils.classCheck(vehicleClass)
        local icon = Config.Icons[vehicleType]
        local ImpoundPrice = dp > 0 and dp or Config.ImpoundPrice[vehicleClass]

        if gState == 0 then
            if vehFunc.govbp(plate) then
                disabled = true
                description = 'STATUS: ' ..  locale('rhd_garage:veh_out_garage')
            else
                description = locale('rhd_garage:impound_price', ImpoundPrice)
            end
        elseif gState == 1 then
            description = 'STATUS: ' ..  locale('rhd_garage:veh_in_garage')
            if shared_garage then
                description = locale('rhd_garage:shared_owner_label', pName) .. ' \n' .. 'STATUS: ' .. locale('rhd_garage:veh_in_garage')
            end
        end

        local vehicleLabel = ('%s [ %s ]'):format(vehlabel, plate)
        
        if Utils.garageType("check", data.type, vehicleType) then
            menuData.options[#menuData.options+1] = {
                title = vehicleLabel,
                icon = icon,
                disabled = disabled,
                description = description:upper(),
                iconAnimation = Config.IconAnimation,
                metadata = {
                    { label = 'Fuel', value = math.floor(fuel) .. '%', progress = math.floor(fuel), colorScheme = Utils.getColorLevel(math.floor(fuel))},
                    { label = 'Body', value = math.floor(body / 10) .. '%', progress = math.floor(body / 10), colorScheme = Utils.getColorLevel(math.floor(body / 10))},
                    { label = 'Engine', value = math.floor(engine/ 10) .. '%', progress = math.floor(engine / 10), colorScheme = Utils.getColorLevel(math.floor(engine / 10))}
                },
                onSelect = function ()
                    local coords = vec(GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0.5), GetEntityHeading(cache.ped)+90)
                    local vehInArea = lib.getClosestVehicle(coords.xyz)
                    if DoesEntityExist(vehInArea) then return Utils.notify(locale('rhd_garage:no_parking_spot'), 'error') end
    
                    VehicleShow = Utils.createPlyVeh(vehModel, coords)
                    NetworkFadeInEntity(VehicleShow, true, false)
                    FreezeEntityPosition(VehicleShow, true)
                    SetVehicleDoorsLocked(VehicleShow, 2)

                    if vehProp and next(vehProp) then
                        vehFunc.svp(VehicleShow, vehProp)
                    end
    
                    actionMenu({
                        prop = vehProp,
                        engine = engine,
                        fuel = fuel,
                        body = body,
                        model = vehModel,
                        plate = plate,
                        coords = coords,
                        garage = data.garage,
                        vehName = vehicleLabel,
                        vehicle_name = vehlabel,
                        impound = data.impound,
                        shared = data.shared,
                        deformation = vehDeformation,
                        depotprice = ImpoundPrice
                    })
                end,
            }
        end
    end

    if #menuData.options < 1 then 
        menuData.options[#menuData.options+1] = {
            title = locale('rhd_garage:no_vehicles_in_garage'):upper(),
            disabled = true
        }
    end

    Utils.createMenu(menuData)
end

local function storeVeh ( data )
    local prop = vehFunc.gvp(data.vehicle)
    local plate = prop.plate:trim()
    local shared = data.shared
    local deformation = Deformation.get(data.vehicle)
    local fuel = Utils.getFuel(data.vehicle)
    local engine = GetVehicleEngineHealth(data.vehicle)
    local body = GetVehicleBodyHealth(data.vehicle)


    local isOwned = lib.callback.await('rhd_garage:cb_server:getvehowner', false, plate, shared, {
        mods = prop,
        deformation = deformation,
        fuel =  fuel,
        engine = engine,
        body = body,
        vehicle_name = Entity(data.vehicle).state.vehlabel
    })

    if not isOwned then return Utils.notify(locale('rhd_garage:not_owned'), 'error') end
    if DoesEntityExist(data.vehicle) then
        SetEntityAsMissionEntity(data.vehicle, true, true)
        DeleteVehicle(data.vehicle)
        
        TriggerServerEvent('rhd_garage:server:updateState', {
            plate = plate,
            state = 1,
            garage = data.garage
        })
        
        Utils.notify(locale('rhd_garage:success_stored'), 'success')
    end
end

--- exports 
exports('openMenu', openMenu)
exports('storeVehicle', storeVeh)
