
local component = require("component")
local computer = require("computer")
local event = require("event")
local sides = require("sides")

local AR = {}

--------------------------------------------------------------------------------

AR.proxies = {}
AR.requiredProxies = {
	["robot"] = true,
	["generator"] = true,
	["inventory_controller"] = true,
	["modem"] = true,
	["geolyzer"] = true,
	["redstone"] = true,
	["experience"] = true,
	["chunkloader"] = true,
}

AR.fuels = {
	["minecraft:coal"] = true,
	["minecraft:coal_block"] = true,
	["minecraft:lava_bucket"] = true,
	["minecraft:coal_block"] = true,
}

AR.droppables = {
	["minecraft:cobblestone"] = true,
	["minecraft:grass"] = true,
	["minecraft:dirt"] = true,
	["minecraft:gravel"] = true,
	["minecraft:sand"] = true,
	["minecraft:sandstone"] = true,
	["minecraft:torch"] = true,
	["minecraft:planks"] = true,
	["minecraft:fence"] = true,
	["minecraft:chest"] = true,
	["minecraft:monster_egg"] = true,
	["minecraft:stonebrick"] = true,
}

AR.tools = {
	["minecraft:diamond_pickaxe"] = true,
	["minecraft:iron_pickaxe"] = true,
}

AR.toolReplaceDurability = 0.05
AR.zeroPositionReturnEnergy = 0.1
AR.emptySlotsCountDropping = 4

AR.positionX = 0
AR.positionY = 0
AR.positionZ = 0
AR.rotation = 0

--------------------------------------------------------------------------------

function AR.updateProxies()
	local name
	for name in pairs(AR.requiredProxies) do
		AR.proxies[name] = component.list(name)()
		if AR.proxies[name] then
			AR.proxies[name] = component.proxy(AR.proxies[name])
		end
	end
end

AR.updateProxies()

for key, value in pairs(AR.proxies.robot) do
	AR[key] = value
end

--------------------------------------------------------------------------------

function AR.move(direction)
	local success, reason = AR.proxies.robot.move(direction)
	
	if success then
		if direction == sides.front or direction == sides.back then
			local directionOffset = direction == sides.front and 1 or -1

			if AR.rotation == 0 then
				AR.positionX = AR.positionX + directionOffset
			elseif AR.rotation == 1 then
				AR.positionZ = AR.positionZ + directionOffset
			elseif AR.rotation == 2 then
				AR.positionX = AR.positionX - directionOffset
			elseif AR.rotation == 3 then
				AR.positionZ = AR.positionZ - directionOffset
			end
		elseif direction == sides.up or direction == sides.down then
			AR.positionY = AR.positionY + (direction == sides.up and 1 or -1)
		end
	end

	return success, reason
end

function AR.turn(clockwise)
	AR.proxies.robot.turn(clockwise)
	AR.rotation = AR.rotation + (clockwise and 1 or -1)
	
	if AR.rotation > 3 then
		AR.rotation = 0
	elseif AR.rotation < 0 then
		AR.rotation = 3
	end
end

function AR.turnToRotation(requiredRotation)
	local difference = AR.rotation - requiredRotation
	if difference ~= 0 then
		local fastestWay
		if difference > 0 then
			fastestWay = difference > 2
		else
			fastestWay = -difference <= 2
		end

		while AR.rotation ~= requiredRotation do
			AR.turn(fastestWay)
		end
	end
end

function AR.moveToPosition(xTarget, yTarget, zTarget)
	local xDistance, yDistance, zDistance = xTarget - AR.positionX, yTarget - AR.positionY, zTarget - AR.positionZ

	if yDistance ~= 0 then
		local direction = yDistance > 0 and sides.up or sides.down
		for i = 1, math.abs(yDistance) do
			AR.move(direction)
		end
	end

	if xDistance ~= 0 then
		AR.turnToRotation(xDistance > 0 and 0 or 2)
		for i = 1, math.abs(xDistance) do
			AR.move(sides.front)
		end
	end

	if zDistance ~= 0 then
		AR.turnToRotation(zDistance > 0 and 1 or 3)
		for i = 1, math.abs(zDistance) do
			AR.move(sides.front)
		end
	end
end

--------------------------------------------------------------------------------

-- Swing
function AR.swingForward()
	return AR.proxies.robot.swing(sides.front)
end

function AR.swingUp()
	return AR.proxies.robot.swing(sides.up)
end

function AR.swingDown()
	return AR.proxies.robot.swing(sides.down)
end
--Use
function AR.useForward()
	return AR.proxies.robot.use(sides.front)
end

function AR.useUp()
	return AR.proxies.robot.use(sides.up)
end

function AR.useDown()
	return AR.proxies.robot.use(sides.down)
end
-- Move
function AR.moveForward()
	return AR.move(sides.front)
end

function AR.moveBackward()
	return AR.move(sides.back)
end

function AR.moveUp()
	return AR.move(sides.up)
end

function AR.moveDown()
	return AR.move(sides.down)
end
-- Turn
function AR.turnLeft()
	return AR.turn(false)
end

function AR.turnRight()
	return AR.turn(true)
end

function AR.turnAround()
	AR.turn(true)
	AR.turn(true)
end

--------------------------------------------------------------------------------

local function callProxyMethod(proxyName, methodName, ...)
	if AR.proxies[proxyName] then
		return AR.proxies[proxyName][methodName](...)
	else
		return false, proxyName .. " component is not available"
	end
end

function AR.equip(...)
	return callProxyMethod("inventory_controller", "equip", ...)
end

function AR.getStackInInternalSlot(...)
	return callProxyMethod("inventory_controller", "getStackInInternalSlot", ...)
end

--------------------------------------------------------------------------------

function AR.moveToZeroPosition()
	AR.moveToPosition(0, AR.positionY, 0)
	AR.turnToRotation(0)
	AR.dropDroppables()
	AR.moveToPosition(0, 0, 0)
end

function AR.swingAndMove(direction)
	while true do
		local swingSuccess, swingReason = AR.swing(direction)
		if swingSuccess or swingReason == "air" then
			local moveSuccess, moveReason = AR.move(direction)
			if moveSuccess then
				return moveSuccess, moveReason
			end
		else
			if swingReason == "block" then
				AR.moveToZeroPosition()
				return false, "Unbreakable block detected, going to base"
			end
		end
	end
end

function AR.getEmptySlotsCount()
	local count = 0
	for slot = 1, AR.inventorySize() do
		if AR.count(slot) == 0 then
			count = count + 1
		end
	end

	return count
end

function AR.dropDroppables(side)
	if AR.getEmptySlotsCount() < AR.emptySlotsCountDropping then 
		print("Trying to drop all shitty resources to free some slots for mining")
		for slot = 1, AR.inventorySize() do
			local stack = AR.getStackInInternalSlot(slot)
			if stack then
				for name in pairs(AR.droppables) do
					if stack.name == name then
						AR.select(slot)
						AR.drop(side or sides.down)
					end
				end
			end
		end

		AR.select(1)
	end
end

function AR.dropAll(side, exceptArray)
	exceptArray = exceptArray or AR.tools
	print("Dropping all mined resources...")

	for slot = 1, AR.inventorySize() do
		local stack = AR.getStackInInternalSlot(slot)
		if stack then
			local droppableItem = true
			
			for exceptItem in pairs(exceptArray) do
				if stack.name == exceptItem then
					droppableItem = false
					break
				end
			end
			
			if droppableItem then
				AR.select(slot)
				AR.drop(side)
			end
		end
	end

	AR.select(1)
end

function AR.checkToolStatus()
	if AR.durability() < AR.toolReplaceDurability then
		print("Equipped tool durability lesser then " .. AR.toolReplaceDurability)
		local success = false
		
		for slot = 1, AR.inventorySize() do
			local stack = AR.getStackInInternalSlot(slot)
			if stack then
				for name in pairs(AR.tools) do
					if stack.name == name and stack.damage / stack.maxDamage < AR.toolReplaceDurability then
						local oldSlot = AR.select()
						AR.select(slot)
						AR.equip()
						AR.select(oldSlot)
						success = true
						break
					end
				end
			end
		end

		if not success then
			AR.moveToZeroPosition()
			error("No one useable tool are found in inventory, going back to base")
		else
			print("Successfullty switched tool to another from inventory")
		end
	end
end

function AR.checkEnergyStatus()
	if computer.energy() / computer.maxEnergy() < AR.zeroPositionReturnEnergy then
		print("Low energy level detected")
		-- Запоминаем старую позицию, шобы суда вернуться
		local x, y, z = AR.positionX, AR.positionY, AR.positionZ
		-- Пиздуем на базу за зарядкой
		AR.moveToZeroPosition()
		-- Заряжаемся, пока энергия не достигнет более-менее максимума
		while computer.energy() / computer.maxEnergy() < 0.99 do
			print("Charging up: " .. math.floor(computer.energy() / computer.maxEnergy() * 100) .. "%")
			os.sleep(1)
		end
		-- Пиздуем обратно
		AR.moveToPosition(x, y, z)
		AR.turnToRotation(oldPosition.rotation)
	end
end

function AR.getSlotWithFuel()
	for slot = 1, AR.inventorySize() do
		local stack = AR.getStackInInternalSlot(slot)
		if stack then
			for name in pairs(AR.fuels) do
				if stack.name == name then
					return slot
				end
			end
		end
	end
end

function AR.checkGeneratorStatus()
	if AR.proxies.generator then
		if AR.proxies.generator.count() == 0 then
			print("Generator is empty, trying to find some fuel in inventory")
			local slot = AR.getSlotWithFuel()
			if slot then
				print("Found slot with fuel: " .. slot)
				local oldSlot = AR.select()
				AR.select(slot)
				AR.proxies.generator.insert()
				AR.select(oldSlot)
				return
			else
				print("Slot with fuel not found")
			end
		end
	end
end

--------------------------------------------------------------------------------

return AR