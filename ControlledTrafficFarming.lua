-- ============================================================= --
-- CONTROLLED TRAFFIC FARMING MOD
-- ============================================================= --

ControlledTrafficFarming = {}

addModEventListener(ControlledTrafficFarming)

function ControlledTrafficFarming:vehicleLoadFinished(superFunc, i3dNode, arguments)
	--print("ControlledTrafficFarming: vehicle loadFinished")
	local loadingState = superFunc(self, i3dNode, arguments)
	
	if self.spec_wheels ~= nil and self.spec_wheels.wheels ~= nil then
	
		local useCompactionWheels
		local vehicleMass = self:getTotalMass()
		local numberOfWheels = table.getn(self.spec_wheels.wheels)
		
		
		if  vehicleMass < 6.50 or
			self.spec_plow ~= nil or
			self.spec_cultivator ~= nil or
			self.spec_sowingMachine ~= nil then
			useCompactionWheels = false
		else
			useCompactionWheels = true
		end
		
		if numberOfWheels > 0 then
			for i=1, numberOfWheels do
				local wheel = self.spec_wheels.wheels[i]
				wheel.isCompactionWheel = useCompactionWheels
			end
			
			--print("Mass = "..tostring(vehicleMass))
			--print("# Wheels = "..tostring(numberOfWheels))
			--print("Compaction: "..tostring(self.spec_wheels.wheels[1].isCompactionWheel))
		end
	end
	
    return loadingState
end

function ControlledTrafficFarming:compactSoilArea(x0, z0, x1, z1, x2, z2)
	--print("COMPACT SOIL AREA")
	local modifier = g_currentMission.densityMapModifiers.updatePlowArea.modifier
	modifier:resetDensityMapAndChannels(g_currentMission.terrainDetailId, g_currentMission.plowCounterFirstChannel, g_currentMission.plowCounterNumChannels)
	modifier:setParallelogramWorldCoords(x0, z0, x1, z1, x2, z2, "ppp")
	modifier:executeSet(0)

	local groundType = 0 --"HERBICIDE"
	FSDensityMapUtil.setGroundTypeLayerArea(x0, z0, x1, z1, x2, z2, groundType)
end

function ControlledTrafficFarming:getIsWheelSoilCompactionAllowed(wheel)
	-- if self:getIsAIActive() then
		-- return false
	-- end
	
	if not g_currentMission.missionInfo.plowingRequiredEnabled then
		return false
	end
	
	if wheel.contact ~= Wheels.WHEEL_GROUND_CONTACT then
		return false
	end
	
	if not wheel.isCompactionWheel then
		return false
	end

	return true
end

function ControlledTrafficFarming:wheelsUpdateWheelDestruction(superFunc, wheel, dt)
	superFunc(self, wheel, dt)

	if self:getIsWheelSoilCompactionAllowed(wheel) then
		local width = 0.5 * wheel.width
		local length = math.min(0.5, 0.5 * wheel.width)
		local x, _, z = localToLocal(wheel.driveNode, wheel.repr, 0, 0, 0)
		local x0, y0, z0 = localToWorld(wheel.repr, x + width, 0, z - length)
		local x1, y1, z1 = localToWorld(wheel.repr, x - width, 0, z - length)
		local x2, y2, z2 = localToWorld(wheel.repr, x + width, 0, z + length)

		if g_currentMission.accessHandler:canFarmAccessLand(self:getActiveFarm(), x0, z0) then
			self:compactSoilArea(x0, z0, x1, z1, x2, z2)
			--self:destroyFruitArea(x0, z0, x1, z1, x2, z2)
		end

		if wheel.additionalWheels ~= nil then
			for _, additionalWheel in pairs(wheel.additionalWheels) do
				local width = 0.5 * additionalWheel.width
				local length = math.min(0.5, 0.5 * additionalWheel.width)
				local refNode = wheel.node

				if wheel.repr ~= wheel.driveNode then
					refNode = wheel.repr
				end

				local xShift, yShift, zShift = localToLocal(additionalWheel.wheelTire, refNode, 0, 0, 0)
				local x0, y0, z0 = localToWorld(refNode, xShift + width, yShift, zShift - length)
				local x1, y1, z1 = localToWorld(refNode, xShift - width, yShift, zShift - length)
				local x2, y2, z2 = localToWorld(refNode, xShift + width, yShift, zShift + length)

				if g_farmlandManager:getIsOwnedByFarmAtWorldPosition(self:getActiveFarm(), x0, z0) then
					self:compactSoilArea(x0, z0, x1, z1, x2, z2)
					--self:destroyFruitArea(x0, z0, x1, z1, x2, z2)
				end
			end
		end
	end
end

function ControlledTrafficFarming:FSBaseMissionGetHarvestScaleMultiplier(superFunc, fruitTypeIndex, sprayFactor, plowFactor, limeFactor, weedFactor)
	if plowFactor == 0 then
		plowFactor = -1
	end
	return superFunc(self, fruitTypeIndex, sprayFactor, plowFactor, limeFactor, weedFactor)
end

function ControlledTrafficFarming:PFBaseMissionGetHarvestScaleMultiplier(superFunc, fruitTypeIndex, sprayFactor, plowFactor, limeFactor, weedFactor)
	if plowFactor == 0 then
		plowFactor = -1
	end
	return superFunc(self, fruitTypeIndex, sprayFactor, plowFactor, limeFactor, weedFactor)
end

function ControlledTrafficFarming:loadMap(name)
	--print("Load Mod: 'Controlled Traffic Farming'")

	if g_modIsLoaded['FS19_precisionFarming'] then
		local pf = getfenv(0).FS19_precisionFarming.g_precisionFarming
		for i = 1, table.getn(pf.overwrittenGameFunctions) do
			if pf.overwrittenGameFunctions[i].funcName == "getHarvestScaleMultiplier" then
				local object = pf.overwrittenGameFunctions[i].object
				object.getHarvestScaleMultiplier = Utils.overwrittenFunction(object.getHarvestScaleMultiplier, ControlledTrafficFarming.PFBaseMissionGetHarvestScaleMultiplier)
			end
		end
	else
		FSBaseMission.getHarvestScaleMultiplier = Utils.overwrittenFunction(FSBaseMission.getHarvestScaleMultiplier, ControlledTrafficFarming.FSBaseMissionGetHarvestScaleMultiplier)
	end
	
	Vehicle.loadFinished = Utils.overwrittenFunction(Vehicle.loadFinished, ControlledTrafficFarming.vehicleLoadFinished)
	
	for name, data in pairs( g_vehicleTypeManager:getVehicleTypes() ) do
		local vehicleType = g_vehicleTypeManager:getVehicleTypeByName(tostring(name))
		if SpecializationUtil.hasSpecialization(Wheels, data.specializations) then
			SpecializationUtil.registerFunction(vehicleType, "compactSoilArea", ControlledTrafficFarming.compactSoilArea)
			SpecializationUtil.registerFunction(vehicleType, "getIsWheelSoilCompactionAllowed", ControlledTrafficFarming.getIsWheelSoilCompactionAllowed)
			SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateWheelDestruction", ControlledTrafficFarming.wheelsUpdateWheelDestruction)
			SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateWheelDestruction", ControlledTrafficFarming.wheelsUpdateWheelDestruction)
		end
	end

	self.initialised = false
end

function ControlledTrafficFarming:deleteMap()
end

function ControlledTrafficFarming:mouseEvent(posX, posY, isDown, isUp, button)
end

function ControlledTrafficFarming:keyEvent(unicode, sym, modifier, isDown)
end

function ControlledTrafficFarming:draw()
end

function ControlledTrafficFarming:update(dt)
	if not self.initialised then
		print("*** Controlled Traffic Farming is loaded ***")
		--for name, fruitType in pairs(g_fruitTypeManager.nameToFruitType) do
		for _, fruitType in ipairs(g_fruitTypeManager:getFruitTypes()) do
			fruitType.increasesSoilDensity = false
		end
		
		self.initialised = true
	end
end

-- ADD custom strings from ModDesc.xml to g_i18n
-- local i = 0
-- local xmlFile = loadXMLFile("modDesc", g_currentModDirectory.."modDesc.xml")
-- while true do
	-- local key = string.format("modDesc.l10n.text(%d)", i)
	
	-- if not hasXMLProperty(xmlFile, key) then
		-- break
	-- end

	-- local name = getXMLString(xmlFile, key.."#name")
	-- local text = getXMLString(xmlFile, key.."."..g_languageShort)

	-- if name == "setting_soilCompaction"	then
		-- g_i18n:setText("setting_plowingRequired", text)
	-- end
		
	-- if name == "toolTip_soilCompaction" then
		-- g_i18n:setText("toolTip_plowingRequired", text)
	-- end
	
	-- i = i + 1
-- end