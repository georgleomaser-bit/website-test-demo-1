--[[
	Instance.luau

	Pure-Lua mock of Roblox Instances.

	Every Instance is a userdata proxy (newproxy) so `type(inst) == "userdata"`
	and `typeof(inst) == "Instance"`, exactly like the engine. Member access is
	validated against the reflection data:
	  * unknown members        -> "X is not a valid member of Class \"Full.Name\""
	  * read-only properties   -> "Unable to assign property X. Property is read only"
	  * wrong value types      -> "Unable to assign property X. UDim2 expected, got number"
	  * engine methods the harness does not implement raise
	    "Harness: Class:Method() is not implemented" so gaps are obvious.

	Class-specific behaviour (methods, computed getters, setters, hooks) is
	registered with Instance.define(className, { ... }) from Classes.luau and
	inherited along the class chain.
]]

local Types = require("./Types")
local Signal = require("./Signal")
local Reflection = require("./Reflection")

local Instance = {}

-- proxy -> state
local states = setmetatable({}, { __mode = "k" })
Instance.states = states

-- className -> { methods, getters, setters, onCreate, onClone, onDestroy, onPropertyChanged, onCallbackSet }
local behaviors = {}
local resolveCache = {}
local defineVersion = 0

function Instance.define(className: string, def)
	assert(Reflection.classExists(className) or className == "Object", "Instance.define: unknown class " .. className)
	local existing = behaviors[className]
	if not existing then
		existing = { methods = {}, getters = {}, setters = {} }
		behaviors[className] = existing
	end
	for kind, value in pairs(def) do
		if kind == "methods" or kind == "getters" or kind == "setters" then
			for k, v in pairs(value) do
				existing[kind][k] = v
			end
		else
			existing[kind] = value
		end
	end
	table.clear(resolveCache)
	defineVersion += 1
end

-- Finds the most-derived behaviour entry for (class, kind, key).
local function resolve(className: string, kind: string, key: string)
	local perClass = resolveCache[className]
	if not perClass then
		perClass = { methods = {}, getters = {}, setters = {} }
		resolveCache[className] = perClass
	end
	local bucket = perClass[kind]
	local cached = bucket[key]
	if cached ~= nil then
		return cached or nil
	end
	local found = nil
	for _, name in ipairs(Reflection.chain(className)) do
		local b = behaviors[name]
		if b and b[kind][key] then
			found = b[kind][key]
			break
		end
	end
	bucket[key] = found or false
	return found
end

-- Hooks are collected base-first so derived classes can extend base behaviour.
local hookCache = {}
local function hooks(className: string, hookName: string)
	local key = className .. "|" .. hookName
	local cached = hookCache[key]
	if cached and cached.version == defineVersion then
		return cached.list
	end
	local list = {}
	local chain = Reflection.chain(className)
	for i = #chain, 1, -1 do
		local b = behaviors[chain[i]]
		if b and b[hookName] then
			table.insert(list, b[hookName])
		end
	end
	hookCache[key] = { list = list, version = defineVersion }
	return list
end

function Instance.is(value: any): boolean
	return states[value] ~= nil
end

function Instance.state(value: any)
	return states[value]
end

local function stateOf(value: any, method: string)
	local st = states[value]
	if not st then
		error("Expected ':' not '.' calling member function " .. method, 3)
	end
	return st
end
Instance.stateOf = stateOf

local function fullName(st): string
	local parts = {}
	local current = st
	while current and current.className ~= "DataModel" do
		table.insert(parts, 1, current.name)
		current = current.parent
	end
	return table.concat(parts, ".")
end
Instance.fullName = fullName

-- Signals ----------------------------------------------------------------------------------

local function getSignal(st, name: string)
	local s = st.signals[name]
	if not s then
		s = Signal.new(st.world.scheduler, st.className .. "." .. name, st.world)
		st.signals[name] = s
		if name == "AncestryChanged" then
			st.world.ancestryListeners += 1
		elseif name == "DescendantAdded" or name == "DescendantRemoving" then
			st.world.descendantListeners += 1
		end
	end
	return s
end
Instance.getSignal = getSignal

local function fire(st, name: string, ...)
	local s = st.signals[name]
	if s then
		s:_fire(...)
	end
end
Instance.fire = fire

-- Children --------------------------------------------------------------------------------

local function findChild(st, name: string)
	for _, child in ipairs(st.children) do
		if child.name == name then
			return child
		end
	end
	return nil
end

local function eachDescendant(st, fn)
	for _, child in ipairs(st.children) do
		fn(child)
		eachDescendant(child, fn)
	end
end
Instance.eachDescendant = eachDescendant

local function notifyChildWaiters(parent, child)
	local waiters = parent.childWaiters and parent.childWaiters[child.name]
	if not waiters then
		return
	end
	parent.childWaiters[child.name] = nil
	for _, entry in ipairs(waiters) do
		if not entry.done then
			entry.done = true
			parent.world.scheduler:resume(entry.thread, child.proxy)
		end
	end
end

-- Property change notification -----------------------------------------------------------------

local function notifyChanged(st, key: string, value: any)
	for _, hook in ipairs(hooks(st.className, "onPropertyChanged")) do
		hook(st, key, value)
	end
	local propSignal = st.propSignals[key]
	if propSignal then
		propSignal:_fire()
	end
	local changed = st.signals.Changed
	if changed then
		if st.isValueBase then
			if key == "Value" then
				changed:_fire(value)
			end
		else
			changed:_fire(key)
		end
	end
	st.world:_onPropertyChanged(st, key, value)
end
Instance.notifyChanged = notifyChanged

-- Raw property write (no validation) used by the harness and class behaviours.
function Instance.setProperty(st, key: string, value: any)
	local old = st.props[key]
	if old == nil then
		local member = Reflection.member(st.className, key)
		if member and member.kind == "property" then
			old = Reflection.default(st.className, member)
		end
	end
	st.props[key] = value
	if old ~= value then
		notifyChanged(st, key, value)
	end
end

function Instance.getProperty(st, key: string)
	local v = st.props[key]
	if v ~= nil then
		return v
	end
	local member = Reflection.member(st.className, key)
	if member and member.kind == "property" then
		return Reflection.default(st.className, member)
	end
	return nil
end

-- Parenting ----------------------------------------------------------------------------------

local function fireAncestryChanged(root, newParentProxy)
	if root.world.ancestryListeners == 0 then
		return
	end
	local function visit(st)
		local s = st.signals.AncestryChanged
		if s then
			s:_fire(root.proxy, newParentProxy)
		end
		for _, child in ipairs(st.children) do
			visit(child)
		end
	end
	visit(root)
end

local function fireDescendantSignal(ancestorStart, st, signalName: string)
	if st.world.descendantListeners == 0 then
		return
	end
	local listeners = {}
	local a = ancestorStart
	while a do
		local s = a.signals[signalName]
		if s then
			table.insert(listeners, s)
		end
		a = a.parent
	end
	if #listeners == 0 then
		return
	end
	local function visit(node)
		for _, s in ipairs(listeners) do
			s:_fire(node.proxy)
		end
		for _, child in ipairs(node.children) do
			visit(child)
		end
	end
	visit(st)
end

local function setParent(st, value: any, force: boolean?)
	if value ~= nil and not states[value] then
		error("Unable to assign property Parent. Instance expected, got " .. Types.typeof(value), 3)
	end
	local newParent = if value ~= nil then states[value] else nil
	if st.parentLocked and not force then
		error(
			string.format(
				"The Parent property of %s is locked, current parent: %s, new parent %s",
				st.name,
				if st.parent then st.parent.name else "NULL",
				if newParent then newParent.name else "NULL"
			),
			3
		)
	end
	if newParent == st.parent then
		return
	end
	if newParent then
		if newParent == st then
			error("Attempt to set " .. fullName(st) .. " as its own parent", 3)
		end
		local p = newParent
		while p do
			if p == st then
				error(
					string.format(
						"Attempt to set parent of %s to %s would result in circular reference",
						fullName(st),
						fullName(newParent)
					),
					3
				)
			end
			p = p.parent
		end
		if newParent.world ~= st.world then
			error("Harness: cannot parent an Instance into a different world (" .. st.world.name .. " -> " .. newParent.world.name .. ")", 3)
		end
		if newParent.destroyed then
			error(string.format("The Parent property of %s is locked", newParent.name), 3)
		end
	end

	local oldParent = st.parent
	if oldParent then
		fireDescendantSignal(oldParent, st, "DescendantRemoving")
		local list = oldParent.children
		for i, child in ipairs(list) do
			if child == st then
				table.remove(list, i)
				break
			end
		end
		st.parent = nil
		fire(oldParent, "ChildRemoved", st.proxy)
	end
	if newParent then
		table.insert(newParent.children, st)
		st.parent = newParent
		fire(newParent, "ChildAdded", st.proxy)
		fireDescendantSignal(newParent, st, "DescendantAdded")
		notifyChildWaiters(newParent, st)
	end
	fireAncestryChanged(st, if newParent then newParent.proxy else nil)
	local propSignal = st.propSignals.Parent
	if propSignal then
		propSignal:_fire()
	end
	local changed = st.signals.Changed
	if changed and not st.isValueBase then
		changed:_fire("Parent")
	end
	st.world:_onParentChanged(st, oldParent, newParent)
end
Instance.setParent = setParent

local function setName(st, value: any)
	local t = Types.typeof(value)
	if t == "number" then
		value = tostring(value)
	elseif t ~= "string" then
		error("Unable to assign property Name. string expected, got " .. t, 3)
	end
	if st.name == value then
		return
	end
	st.name = value
	notifyChanged(st, "Name", value)
	if st.parent then
		notifyChildWaiters(st.parent, st)
	end
end

-- Destroy / Clone ------------------------------------------------------------------------------

local function destroy(st)
	if st.destroyed then
		return
	end
	fire(st, "Destroying")
	for _, hook in ipairs(hooks(st.className, "onDestroy")) do
		hook(st)
	end
	setParent(st, nil, true)
	st.parentLocked = true
	st.destroyed = true
	for _, child in ipairs(table.clone(st.children)) do
		destroy(child)
	end
	for _, s in pairs(st.signals) do
		s:_disconnectAll()
	end
	for _, s in pairs(st.propSignals) do
		s:_disconnectAll()
	end
	for _, s in pairs(st.attrSignals) do
		s:_disconnectAll()
	end
end
Instance.destroy = destroy

local create -- forward declaration

local function cloneTree(st, map)
	if st.props.Archivable == false then
		return nil
	end
	local copyProxy = create(st.world, st.className, true)
	local copy = states[copyProxy]
	map[st] = copy
	copy.name = st.name
	for k, v in pairs(st.props) do
		copy.props[k] = v
	end
	for k, v in pairs(st.attributes) do
		copy.attributes[k] = v
	end
	for k, v in pairs(st.tags) do
		copy.tags[k] = v
	end
	for _, hook in ipairs(hooks(st.className, "onClone")) do
		hook(st, copy)
	end
	for _, child in ipairs(st.children) do
		local childCopy = cloneTree(child, map)
		if childCopy then
			table.insert(copy.children, childCopy)
			childCopy.parent = copy
		end
	end
	return copy
end

local function clone(st)
	local map = {}
	local copy = cloneTree(st, map)
	if not copy then
		return nil
	end
	-- Remap Ref properties that point inside the cloned subtree.
	for original, dup in pairs(map) do
		for k, v in pairs(original.props) do
			local target = states[v]
			if target and map[target] then
				dup.props[k] = map[target].proxy
			end
		end
	end
	return copy
end
Instance.clone = clone

-- Attributes ---------------------------------------------------------------------------------

local function validateAttributeName(name: any)
	if type(name) ~= "string" then
		error("Attribute name must be a string", 3)
	end
	if #name > 100 then
		error("Attribute name is too long (max 100 characters)", 3)
	end
	if not string.match(name, "^[%w_]+$") then
		error("Attribute name '" .. name .. "' contains invalid characters", 3)
	end
	if string.sub(name, 1, 3) == "RBX" then
		error("Attribute name '" .. name .. "' is reserved", 3)
	end
end

function Instance.setAttribute(st, name: string, value: any)
	local old = st.attributes[name]
	st.attributes[name] = value
	if old == value then
		return
	end
	local s = st.attrSignals[name]
	if s then
		s:_fire()
	end
	fire(st, "AttributeChanged", name)
	st.world:_onAttributeChanged(st, name, value)
end

-- Core Instance methods ---------------------------------------------------------------------------

local function wrapChildren(list)
	local out = table.create(#list)
	for i, child in ipairs(list) do
		out[i] = child.proxy
	end
	return out
end

local function findFirstChild(self, name, recursive)
	local st = stateOf(self, "FindFirstChild")
	if name == nil then
		error("Argument 1 missing or nil", 2)
	end
	name = tostring(name)
	local child = findChild(st, name)
	if child then
		return child.proxy
	end
	if recursive then
		local found = nil
		local function visit(node)
			for _, c in ipairs(node.children) do
				if c.name == name then
					found = c
					return true
				end
				if visit(c) then
					return true
				end
			end
			return false
		end
		visit(st)
		return found and found.proxy
	end
	return nil
end

local function waitForChild(self, name, timeout)
	local st = stateOf(self, "WaitForChild")
	if type(name) ~= "string" then
		error("Argument 1 missing or nil", 2)
	end
	local child = findChild(st, name)
	if child then
		return child.proxy
	end
	local scheduler = st.world.scheduler
	local thread = coroutine.running()
	local entry = { thread = thread, done = false }
	st.childWaiters = st.childWaiters or {}
	st.childWaiters[name] = st.childWaiters[name] or {}
	table.insert(st.childWaiters[name], entry)
	if timeout ~= nil then
		scheduler:after(timeout, function()
			if not entry.done then
				entry.done = true
				scheduler:resume(thread, nil)
			end
		end, st.world)
	else
		scheduler:after(5, function()
			if not entry.done then
				st.world:log(
					"warn",
					string.format("Infinite yield possible on '%s:WaitForChild(\"%s\")'", fullName(st), name)
				)
			end
		end, st.world)
	end
	return scheduler:suspend()
end

local CoreMethods = {
	FindFirstChild = findFirstChild,
	findFirstChild = findFirstChild,
	WaitForChild = waitForChild,
	FindFirstChildOfClass = function(self, className)
		local st = stateOf(self, "FindFirstChildOfClass")
		for _, child in ipairs(st.children) do
			if child.className == className then
				return child.proxy
			end
		end
		return nil
	end,
	FindFirstChildWhichIsA = function(self, className, recursive)
		local st = stateOf(self, "FindFirstChildWhichIsA")
		local function visit(node)
			for _, child in ipairs(node.children) do
				if Reflection.isA(child.className, className) then
					return child
				end
			end
			if recursive then
				for _, child in ipairs(node.children) do
					local found = visit(child)
					if found then
						return found
					end
				end
			end
			return nil
		end
		local found = visit(st)
		return found and found.proxy
	end,
	FindFirstAncestor = function(self, name)
		local st = stateOf(self, "FindFirstAncestor")
		local p = st.parent
		while p do
			if p.name == name then
				return p.proxy
			end
			p = p.parent
		end
		return nil
	end,
	FindFirstAncestorOfClass = function(self, className)
		local st = stateOf(self, "FindFirstAncestorOfClass")
		local p = st.parent
		while p do
			if p.className == className then
				return p.proxy
			end
			p = p.parent
		end
		return nil
	end,
	FindFirstAncestorWhichIsA = function(self, className)
		local st = stateOf(self, "FindFirstAncestorWhichIsA")
		local p = st.parent
		while p do
			if Reflection.isA(p.className, className) then
				return p.proxy
			end
			p = p.parent
		end
		return nil
	end,
	FindFirstDescendant = function(self, name)
		return findFirstChild(self, name, true)
	end,
	GetChildren = function(self)
		return wrapChildren(stateOf(self, "GetChildren").children)
	end,
	getChildren = function(self)
		return wrapChildren(stateOf(self, "getChildren").children)
	end,
	children = function(self)
		return wrapChildren(stateOf(self, "children").children)
	end,
	GetDescendants = function(self)
		local st = stateOf(self, "GetDescendants")
		local out = {}
		eachDescendant(st, function(d)
			table.insert(out, d.proxy)
		end)
		return out
	end,
	IsA = function(self, className)
		local st = stateOf(self, "IsA")
		return Reflection.isA(st.className, className)
	end,
	isA = function(self, className)
		return Reflection.isA(stateOf(self, "isA").className, className)
	end,
	IsDescendantOf = function(self, ancestor)
		local st = stateOf(self, "IsDescendantOf")
		local target = states[ancestor]
		if ancestor ~= nil and not target then
			error("Argument 1 missing or nil", 2)
		end
		local p = st.parent
		while p do
			if p == target then
				return true
			end
			p = p.parent
		end
		return false
	end,
	isDescendantOf = function(self, ancestor)
		local st = stateOf(self, "isDescendantOf")
		local target = states[ancestor]
		local p = st.parent
		while p do
			if p == target then
				return true
			end
			p = p.parent
		end
		return false
	end,
	IsAncestorOf = function(self, descendant)
		local st = stateOf(self, "IsAncestorOf")
		local d = states[descendant]
		if not d then
			return false
		end
		local p = d.parent
		while p do
			if p == st then
				return true
			end
			p = p.parent
		end
		return false
	end,
	GetFullName = function(self)
		return fullName(stateOf(self, "GetFullName"))
	end,
	Destroy = function(self)
		destroy(stateOf(self, "Destroy"))
	end,
	destroy = function(self)
		destroy(stateOf(self, "destroy"))
	end,
	Remove = function(self)
		setParent(stateOf(self, "Remove"), nil)
	end,
	remove = function(self)
		setParent(stateOf(self, "remove"), nil)
	end,
	ClearAllChildren = function(self)
		local st = stateOf(self, "ClearAllChildren")
		for _, child in ipairs(table.clone(st.children)) do
			destroy(child)
		end
	end,
	Clone = function(self)
		local copy = clone(stateOf(self, "Clone"))
		return copy and copy.proxy
	end,
	clone = function(self)
		local copy = clone(stateOf(self, "clone"))
		return copy and copy.proxy
	end,
	SetAttribute = function(self, name, value)
		local st = stateOf(self, "SetAttribute")
		validateAttributeName(name)
		if value ~= nil then
			local t = Types.typeof(value)
			if not Types.AttributeTypes[t] then
				error(t .. " is not a supported attribute type", 2)
			end
		end
		Instance.setAttribute(st, name, value)
	end,
	GetAttribute = function(self, name)
		local st = stateOf(self, "GetAttribute")
		if type(name) ~= "string" then
			error("Argument 1 missing or nil", 2)
		end
		return st.attributes[name]
	end,
	GetAttributes = function(self)
		return table.clone(stateOf(self, "GetAttributes").attributes)
	end,
	GetAttributeChangedSignal = function(self, name)
		local st = stateOf(self, "GetAttributeChangedSignal")
		local s = st.attrSignals[name]
		if not s then
			s = Signal.new(st.world.scheduler, "AttributeChanged:" .. tostring(name), st.world)
			st.attrSignals[name] = s
		end
		return s
	end,
	GetPropertyChangedSignal = function(self, property)
		local st = stateOf(self, "GetPropertyChangedSignal")
		local member = Reflection.member(st.className, property)
		if not (member and member.kind == "property") and property ~= "Name" and property ~= "Parent" then
			error(tostring(property) .. " is not a valid property name.", 2)
		end
		local s = st.propSignals[property]
		if not s then
			s = Signal.new(st.world.scheduler, "PropertyChanged:" .. tostring(property), st.world)
			st.propSignals[property] = s
		end
		return s
	end,
	AddTag = function(self, tag)
		local st = stateOf(self, "AddTag")
		if not st.tags[tag] then
			st.tags[tag] = true
			st.world:_onTagChanged(st, tag, true)
		end
	end,
	RemoveTag = function(self, tag)
		local st = stateOf(self, "RemoveTag")
		if st.tags[tag] then
			st.tags[tag] = nil
			st.world:_onTagChanged(st, tag, false)
		end
	end,
	HasTag = function(self, tag)
		return stateOf(self, "HasTag").tags[tag] == true
	end,
	GetTags = function(self)
		local out = {}
		for tag in pairs(stateOf(self, "GetTags").tags) do
			table.insert(out, tag)
		end
		table.sort(out)
		return out
	end,
	GetActor = function()
		return nil
	end,
	IsPropertyModified = function(self, property)
		return stateOf(self, "IsPropertyModified").props[property] ~= nil
	end,
	ResetPropertyToDefault = function(self, property)
		local st = stateOf(self, "ResetPropertyToDefault")
		local member = Reflection.member(st.className, property)
		if member and member.kind == "property" then
			Instance.setProperty(st, property, nil)
		end
	end,
}

Instance.CoreMethods = CoreMethods

-- Metamethods -------------------------------------------------------------------------------------

local function unimplemented(className: string, method: string)
	return function()
		error(string.format("Harness: %s:%s() is not implemented in the mock engine", className, method), 2)
	end
end

local function index(proxy, key)
	local st = states[proxy]
	if type(key) ~= "string" then
		error(string.format("%s is not a valid member of %s", tostring(key), st.className), 2)
	end
	if key == "Name" then
		return st.name
	elseif key == "Parent" then
		return st.parent and st.parent.proxy
	elseif key == "ClassName" then
		return st.className
	end
	local method = resolve(st.className, "methods", key)
	if method then
		return method
	end
	local core = CoreMethods[key]
	if core then
		return core
	end
	local getter = resolve(st.className, "getters", key)
	if getter then
		return getter(st, key)
	end
	local member = Reflection.member(st.className, key)
	if member then
		if member.kind == "property" then
			if member.scriptability == "Read" or member.scriptability == "ReadWrite" then
				local v = st.props[key]
				if v ~= nil then
					return v
				end
				return Reflection.default(st.className, member)
			end
		elseif member.kind == "event" then
			return getSignal(st, key)
		elseif member.kind == "method" then
			return unimplemented(st.className, key)
		elseif member.kind == "callback" then
			error(
				string.format(
					"%s is a callback member of %s; you can only set the callback value, get is not available",
					key,
					st.className
				),
				2
			)
		end
	end
	local child = findChild(st, key)
	if child then
		return child.proxy
	end
	error(string.format('%s is not a valid member of %s "%s"', key, st.className, fullName(st)), 2)
end

local function newindex(proxy, key, value)
	local st = states[proxy]
	if key == "Name" then
		setName(st, value)
		return
	elseif key == "Parent" then
		setParent(st, value)
		return
	end
	if type(key) ~= "string" then
		error(string.format("%s is not a valid member of %s", tostring(key), st.className), 2)
	end
	local setter = resolve(st.className, "setters", key)
	if setter then
		setter(st, value, key)
		return
	end
	local member = Reflection.member(st.className, key)
	if not member then
		error(string.format('%s is not a valid member of %s "%s"', key, st.className, fullName(st)), 2)
	end
	if member.kind == "property" then
		if member.scriptability == "Read" then
			error(string.format("Unable to assign property %s. Property is read only", key), 2)
		elseif member.scriptability ~= "ReadWrite" then
			error(string.format('%s is not a valid member of %s "%s"', key, st.className, fullName(st)), 2)
		end
		local ok, coerced = pcall(Reflection.coerce, member, value, Instance.is)
		if not ok then
			error(coerced, 2)
		end
		Instance.setProperty(st, key, coerced)
	elseif member.kind == "callback" then
		if value ~= nil and type(value) ~= "function" then
			error(string.format("Unable to assign callback %s. function expected, got %s", key, Types.typeof(value)), 2)
		end
		st.callbacks[key] = value
		for _, hook in ipairs(hooks(st.className, "onCallbackSet")) do
			hook(st, key, value)
		end
	else
		error(string.format("%s cannot be assigned to", key), 2)
	end
end

local function tostringFn(proxy)
	local st = states[proxy]
	return if st then st.name else "Instance"
end

-- Creation ------------------------------------------------------------------------------------

-- internal = true bypasses the creatable check (services, Player, InputObject ...).
create = function(world, className: string, internal: boolean?)
	if type(className) ~= "string" or not Reflection.classExists(className) then
		error(string.format('Unable to create an Instance of type "%s"', tostring(className)), 3)
	end
	if not internal and not Reflection.isCreatable(className) then
		error(string.format('Unable to create an Instance of type "%s"', className), 3)
	end
	local proxy = newproxy(true)
	local mt = getmetatable(proxy)
	mt.__index = index
	mt.__newindex = newindex
	mt.__tostring = tostringFn
	mt.__metatable = "The metatable is locked"
	local st = {
		world = world,
		className = className,
		name = className,
		props = {},
		children = {},
		parent = nil,
		attributes = {},
		tags = {},
		signals = {},
		propSignals = {},
		attrSignals = {},
		callbacks = {},
		internal = {},
		destroyed = false,
		parentLocked = false,
		proxy = proxy,
		isValueBase = Reflection.isA(className, "ValueBase"),
	}
	states[proxy] = st
	Types.register(proxy, "Instance")
	world.instanceCount += 1
	for _, hook in ipairs(hooks(className, "onCreate")) do
		hook(st)
	end
	return proxy
end

function Instance.create(world, className: string, internal: boolean?)
	return create(world, className, internal)
end

-- The global `Instance` table given to scripts in a world.
function Instance.makeGlobal(world)
	return table.freeze({
		new = function(className, parent)
			local proxy = create(world, className, false)
			if parent ~= nil then
				setParent(states[proxy], parent)
			end
			return proxy
		end,
		fromExisting = function(existing)
			local st = states[existing]
			if not st then
				error("Instance.fromExisting expects an Instance", 2)
			end
			local copy = create(world, st.className, false)
			local cst = states[copy]
			cst.name = st.name
			for k, v in pairs(st.props) do
				cst.props[k] = v
			end
			return copy
		end,
	})
end

return Instance
