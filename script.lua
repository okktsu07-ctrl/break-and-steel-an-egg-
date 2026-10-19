--[[ Script source: https://robscript.com/break-and-steal-an-egg-scripts/#speed-anti-knockback ]]

local SPEED = 200
local REFRESH_INTERVAL = 0.1

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Run this script on the client")
assert(game.PlaceId == 114326934417838, "Wrong game")

local modules = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Modules")
local controllers = modules.Parent:WaitForChild("Controllers")
local movementLock = require(modules:WaitForChild("MovementLock"))
local slowMode = require(controllers:WaitForChild("SlowModeController"))
local movementRemote = ReplicatedStorage:WaitForChild("SlowModeRemote", 10)
assert(movementRemote and movementRemote:IsA("RemoteEvent"), "Movement remote unavailable")

local environment = getgenv()
local previous = environment.EggSpeedController
if previous and type(previous.Destroy) == "function" then
    previous:Destroy()
end

local previousGui = environment.EggSpeedGui
if previousGui and type(previousGui.Destroy) == "function" then
    previousGui:Destroy()
end

local antiKnockback

local function startAntiKnockback()
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local player = Players.LocalPlayer
    assert(player, "Run this script on the client")
    assert(game.PlaceId == 114326934417838, "Wrong game")
    assert(type(getconnections) == "function", "getconnections is unavailable")
    assert(type(getfenv) == "function", "getfenv is unavailable")

    local remote = ReplicatedStorage:WaitForChild("CatchFlingRemote", 10)
    assert(remote and remote:IsA("RemoteEvent"), "CatchFlingRemote is unavailable")

    local environment = getgenv()
    local previous = environment.EggAntiKnockbackController
    if previous and type(previous.Destroy) == "function" then
        previous:Destroy()
    end

    local controller = { Enabled = false, BlockedFlings = 0 }
    local intercepted = {}
    local connections = {}
    local destroyed = false
    local suppressUntil = 0
    local lastScan = 0

    local function stopKnockback()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            return
        end
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and not part.Anchored then
                part.AssemblyLinearVelocity = Vector3.zero
                part.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end

    local function restoreListeners()
        for _, entry in ipairs(intercepted) do
            entry.Replacement:Disconnect()
            pcall(function()
                entry.Original:Enable()
            end)
        end
        table.clear(intercepted)
    end

    local function isFlingListener(listener)
        local ok, matches = pcall(function()
            if not listener.Enabled or type(listener.Function) ~= "function" then
                return false
            end
            local owner = getfenv(listener.Function).script
            return typeof(owner) == "Instance" and owner.Name == "CatchFlingController"
        end)
        return ok and matches
    end

    local function interceptListeners()
        for _, listener in ipairs(getconnections(remote.OnClientEvent)) do
            if isFlingListener(listener) then
                local original = listener.Function
                local replacement = remote.OnClientEvent:Connect(function(action, ...)
                    if destroyed or not controller.Enabled then
                        return
                    end
                    if action == "fling" then
                        controller.BlockedFlings = controller.BlockedFlings + 1
                        suppressUntil = os.clock() + 0.35
                        stopKnockback()
                        return
                    end
                    if action == "release" then
                        suppressUntil = 0
                    end
                    original(action, ...)
                end)
                local ok, err = pcall(function()
                    listener:Disable()
                end)
                if not ok then
                    replacement:Disconnect()
                    error(err)
                end
                table.insert(intercepted, {
                    Original = listener,
                    Callback = original,
                    Replacement = replacement,
                })
            end
        end
    end

    function controller:SetEnabled(enabled)
        if destroyed then
            return
        end
        enabled = enabled == true
        if self.Enabled == enabled then
            return
        end
        suppressUntil = 0
        if not enabled then
            self.Enabled = false
            restoreListeners()
            return
        end
        local ok, err = pcall(interceptListeners)
        if not ok or #intercepted == 0 then
            restoreListeners()
            error(err or "CatchFlingController listener not found; wait for the game to load")
        end
        self.Enabled = true
        lastScan = os.clock()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0
            and humanoid:GetState() == Enum.HumanoidStateType.Physics then
            for _, entry in ipairs(intercepted) do
                pcall(entry.Callback, "release")
            end
            stopKnockback()
        end
    end

    function controller:Destroy()
        if destroyed then
            return
        end
        destroyed = true
        self.Enabled = false
        suppressUntil = 0
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        restoreListeners()
        if environment.EggAntiKnockbackController == self then
            environment.EggAntiKnockbackController = nil
        end
    end

    local function step()
        if controller.Enabled and os.clock() < suppressUntil then
            stopKnockback()
        end
    end

    controller:SetEnabled(true)
    table.insert(connections, RunService.PreSimulation:Connect(step))
    table.insert(connections, RunService.PostSimulation:Connect(step))
    table.insert(connections, player.CharacterAdded:Connect(function()
        suppressUntil = 0
    end))
    table.insert(connections, RunService.Heartbeat:Connect(function()
        if not controller.Enabled or os.clock() - lastScan < 1 then
            return
        end
        lastScan = os.clock()
        local ok, err = pcall(interceptListeners)
        if not ok then
            warn("Anti-knockback listener update failed: " .. tostring(err))
        end
    end))

    environment.EggAntiKnockbackController = controller
    return controller
end

local controller = { Speed = SPEED, Enabled = false }
local originalMode = slowMode.IsOn()
local currentMode = originalMode
local refreshing = false
local lastRefresh = -math.huge
local connection
local lastRoot
local destroyed = false
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

environment.EggSpeedController = controller

local function restoreMode()
    if refreshing then
        refreshing = false
        currentMode = originalMode
        movementRemote:FireServer(originalMode)
        lastRefresh = -math.huge
    end
end

function controller:SetSpeed(value)
    assert(type(value) == "number" and value > 0 and value < math.huge,
        "Speed must be a positive finite number")
    self.Speed = value
end

local function stopVelocity()
    if lastRoot and lastRoot.Parent and not lastRoot.Anchored then
        local velocity = lastRoot.AssemblyLinearVelocity
        lastRoot.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
    end
    lastRoot = nil
end

function controller:SetEnabled(value)
    if destroyed then
        return
    end
    self.Enabled = value == true
    if not self.Enabled then
        restoreMode()
        stopVelocity()
    end
end

function controller:Destroy()
    if destroyed then
        return
    end
    destroyed = true
    if connection then
        connection:Disconnect()
    end
    restoreMode()
    stopVelocity()
    if environment.EggSpeedController == self then
        environment.EggSpeedController = nil
    end
end

connection = RunService.PreSimulation:Connect(function()
    if not controller.Enabled then
        return
    end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not root or humanoid.Health <= 0 or root.Anchored
        or humanoid.Sit or humanoid.PlatformStand or movementLock.IsLocked()
        or humanoid:GetState() == Enum.HumanoidStateType.Physics then
        restoreMode()
        return
    end
    local speed = controller.Speed
    if type(speed) ~= "number" or speed <= 0 or speed >= math.huge or speed ~= speed then
        restoreMode()
        return
    end
    local direction = humanoid.MoveDirection
    if direction.Magnitude > 0.01 then
        local now = os.clock()
        if now - lastRefresh >= REFRESH_INTERVAL then
            refreshing = true
            currentMode = not currentMode
            movementRemote:FireServer(currentMode)
            lastRefresh = now
        end
    else
        restoreMode()
    end
    local floorVelocity = Vector3.zero
    if humanoid.FloorMaterial ~= Enum.Material.Air then
        raycastParams.FilterDescendantsInstances = { character }
        local distance = humanoid.HipHeight + root.Size.Y * 0.5 + 2
        local floor = workspace:Raycast(root.Position, Vector3.new(0, -distance, 0), raycastParams)
        if floor and floor.Instance:IsA("BasePart") then
            floorVelocity = floor.Instance:GetVelocityAtPosition(floor.Position)
        end
    end
    local velocity = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(
        direction.X * speed + floorVelocity.X,
        velocity.Y,
        direction.Z * speed + floorVelocity.Z
    )
    lastRoot = root
end)


local UserInputService = game:GetService("UserInputService")
local MIN_SPEED, MAX_SPEED = 16, 400
local connections = {}
local guiDestroyed = false
local guiController = {}

local function connect(signal, callback)
    local listener = signal:Connect(callback)
    table.insert(connections, listener)
    return listener
end

local function create(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function corner(parent, radius)
    create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local colors = {
    Panel = Color3.fromRGB(8, 8, 8),
    Surface = Color3.fromRGB(16, 16, 16),
    Border = Color3.fromRGB(80, 80, 80),
    Text = Color3.fromRGB(235, 235, 235),
    Muted = Color3.fromRGB(145, 145, 145),
    Accent = Color3.fromRGB(170, 170, 170),
}

local screen = create("ScreenGui", {
    Name = "EggSpeedGui",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 100,
}, player:WaitForChild("PlayerGui"))

local panel = create("Frame", {
    Name = "Panel",
    Size = UDim2.fromOffset(330, 148),
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = colors.Panel,
    BorderSizePixel = 0,
    Active = true,
}, screen)
corner(panel, 6)
create("UIStroke", { Color = colors.Border, Thickness = 1 }, panel)

local header = create("Frame", {
    Name = "DragHeader",
    Size = UDim2.new(1, -54, 0, 48),
    BackgroundTransparency = 1,
    Active = true,
}, panel)
create("TextLabel", {
    Size = UDim2.new(1, -20, 1, 0),
    Position = UDim2.fromOffset(20, 0),
    BackgroundTransparency = 1,
    Text = "SPEED",
    Font = Enum.Font.GothamBold,
    TextSize = 14,
    TextColor3 = colors.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local close = create("TextButton", {
    Name = "Close",
    Size = UDim2.fromOffset(24, 24),
    Position = UDim2.new(1, -44, 0, 12),
    BackgroundTransparency = 1,
    Text = "×",
    Font = Enum.Font.Gotham,
    TextSize = 22,
    TextColor3 = colors.Muted,
    AutoButtonColor = false,
}, panel)

create("Frame", {
    Size = UDim2.new(1, -40, 0, 1),
    Position = UDim2.fromOffset(20, 48),
    BackgroundColor3 = colors.Border,
    BorderSizePixel = 0,
}, panel)

local controlRow = create("Frame", {
    Name = "ControlRow",
    Size = UDim2.new(1, -40, 0, 32),
    Position = UDim2.fromOffset(20, 68),
    BackgroundTransparency = 1,
}, panel)
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 16),
}, controlRow)

local slider = create("TextButton", {
    Name = "Slider",
    LayoutOrder = 2,
    Size = UDim2.new(1, -88, 0, 32),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
}, controlRow)
local track = create("Frame", {
    AnchorPoint = Vector2.new(0, 0.5),
    Size = UDim2.new(1, -12, 0, 4),
    Position = UDim2.new(0, 6, 0.5, 0),
    BackgroundColor3 = colors.Surface,
    BorderSizePixel = 0,
    Active = false,
}, slider)
corner(track, 2)
create("UIStroke", { Color = colors.Border, Thickness = 1 }, track)
local fill = create("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = colors.Accent,
    BorderSizePixel = 0,
}, track)
corner(fill, 2)
local thumb = create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(12, 16),
    Position = UDim2.fromScale(0, 0.5),
    BackgroundColor3 = colors.Surface,
    BorderSizePixel = 0,
    ZIndex = 2,
}, track)
corner(thumb, 3)
create("UIStroke", { Color = colors.Accent, Thickness = 1 }, thumb)

local toggle = create("TextButton", {
    Name = "Toggle",
    LayoutOrder = 1,
    Size = UDim2.fromOffset(72, 32),
    BackgroundColor3 = colors.Surface,
    BorderSizePixel = 0,
    Text = "OFF",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = colors.Muted,
    AutoButtonColor = true,
}, controlRow)
corner(toggle, 4)
local toggleStroke = create("UIStroke", {
    Color = colors.Border,
    Thickness = 1,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toggle)

create("TextLabel", {
    Name = "DiscordLink",
    AnchorPoint = Vector2.new(0.5, 1),
    Size = UDim2.new(1, -40, 0, 18),
    Position = UDim2.new(0.5, 0, 1, -16),
    BackgroundTransparency = 1,
    Text = "https://discord.gg/hEbP6rWKy2",
    Font = Enum.Font.Gotham,
    TextSize = 12,
    TextColor3 = colors.Muted,
    TextXAlignment = Enum.TextXAlignment.Center,
}, panel)

local function updateSlider(value)
    value = math.clamp(math.floor(value + 0.5), MIN_SPEED, MAX_SPEED)
    controller:SetSpeed(value)
    local fraction = (value - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)
    fill.Size = UDim2.fromScale(fraction, 1)
    thumb.Position = UDim2.fromScale(fraction, 0.5)
end

local function setEnabled(enabled)
    controller:SetEnabled(enabled)
    toggle.Text = controller.Enabled and "ON" or "OFF"
    toggle.BackgroundColor3 = colors.Surface
    toggle.TextColor3 = controller.Enabled and colors.Text or colors.Muted
    toggleStroke.Color = controller.Enabled and colors.Accent or colors.Border
end

function guiController:Destroy()
    if guiDestroyed then
        return
    end
    guiDestroyed = true
    for _, listener in ipairs(connections) do
        listener:Disconnect()
    end
    controller:Destroy()
    if antiKnockback then
        antiKnockback:Destroy()
    end
    screen:Destroy()
    if environment.EggSpeedGui == self then
        environment.EggSpeedGui = nil
    end
end

environment.EggSpeedGui = guiController
connect(close.Activated, function()
    guiController:Destroy()
end)
connect(screen.Destroying, function()
    guiController:Destroy()
end)
connect(toggle.Activated, function()
    setEnabled(not controller.Enabled)
end)

local sliderInput
local draggingSlider = false
local draggingPanel = false
local panelInput
local dragStart
local panelStart

local function sliderAt(position)
    if track.AbsoluteSize.X > 0 then
        local fraction = math.clamp(
            (position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1
        )
        updateSlider(MIN_SPEED + fraction * (MAX_SPEED - MIN_SPEED))
    end
end

connect(slider.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = true
        sliderInput = input
        sliderAt(input.Position)
    end
end)
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingPanel = true
        panelInput = input
        dragStart = input.Position
        panelStart = panel.Position
    end
end)
connect(UserInputService.InputChanged, function(input)
    local mouseMoved = input.UserInputType == Enum.UserInputType.MouseMovement
    if draggingSlider and (input == sliderInput
        or (sliderInput.UserInputType == Enum.UserInputType.MouseButton1 and mouseMoved)) then
        sliderAt(input.Position)
    end
    if draggingPanel and (input == panelInput
        or (panelInput.UserInputType == Enum.UserInputType.MouseButton1 and mouseMoved)) then
        local delta = input.Position - dragStart
        local viewport = screen.AbsoluteSize
        local size = panel.AbsoluteSize
        local x = panelStart.X.Scale * viewport.X + panelStart.X.Offset + delta.X
        local y = panelStart.Y.Scale * viewport.Y + panelStart.Y.Offset + delta.Y
        x = math.clamp(x, size.X * 0.5, math.max(size.X * 0.5, viewport.X - size.X * 0.5))
        y = math.clamp(y, size.Y * 0.5, math.max(size.Y * 0.5, viewport.Y - size.Y * 0.5))
        panel.Position = UDim2.fromOffset(x, y)
    end
end)
connect(UserInputService.InputEnded, function(input)
    if input == sliderInput then
        draggingSlider = false
        sliderInput = nil
    end
    if input == panelInput then
        draggingPanel = false
        panelInput = nil
    end
end)

updateSlider(SPEED)
setEnabled(false)
local ok, result = pcall(startAntiKnockback)
if not ok then
    guiController:Destroy()
    error(result, 0)
end
antiKnockback = result
guiController.AntiKnockback = antiKnockback
return guiController
