local Layout = {
	ReferenceViewportWidth = 1280,
	ReferenceViewportHeight = 720,
	ReferenceWindowWidth = 680,
	ReferenceWindowHeight = 380,
	MinimumWindowWidth = 500,
	MinimumWindowHeight = 280,
	MaximumWindowWidth = 840,
	MaximumWindowHeight = 500,
	MinimumVisibleWidth = 120,
	TitleBarHeight = 32,
	ViewportMargin = 8,
}

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function round(value)
	return math.floor(value + 0.5)
end

local function viewportSize(width, height)
	return math.max(1, tonumber(width) or Layout.ReferenceViewportWidth),
		math.max(1, tonumber(height) or Layout.ReferenceViewportHeight)
end

local function usableViewport(width, height)
	width, height = viewportSize(width, height)

	return math.max(1, width - Layout.ViewportMargin * 2), math.max(1, height - Layout.ViewportMargin * 2)
end

function Layout.GetSizeBounds(viewportWidth, viewportHeight)
	local availableWidth, availableHeight = usableViewport(viewportWidth, viewportHeight)
	local maximumWidth = math.min(Layout.MaximumWindowWidth, availableWidth)
	local maximumHeight = math.min(Layout.MaximumWindowHeight, availableHeight)
	local minimumWidth = math.min(Layout.MinimumWindowWidth, maximumWidth)
	local minimumHeight = math.min(Layout.MinimumWindowHeight, maximumHeight)

	return minimumWidth, minimumHeight, maximumWidth, maximumHeight
end

function Layout.FitSize(viewportWidth, viewportHeight, width, height)
	local minimumWidth, minimumHeight, maximumWidth, maximumHeight = Layout.GetSizeBounds(viewportWidth, viewportHeight)

	return clamp(round(tonumber(width) or minimumWidth), minimumWidth, maximumWidth),
		clamp(round(tonumber(height) or minimumHeight), minimumHeight, maximumHeight)
end

function Layout.GetDefaultSize(viewportWidth, viewportHeight)
	viewportWidth, viewportHeight = viewportSize(viewportWidth, viewportHeight)

	local scale =
		math.min(viewportWidth / Layout.ReferenceViewportWidth, viewportHeight / Layout.ReferenceViewportHeight)

	return Layout.FitSize(
		viewportWidth,
		viewportHeight,
		Layout.ReferenceWindowWidth * scale,
		Layout.ReferenceWindowHeight * scale
	)
end

function Layout.GetCenteredPosition(viewportWidth, viewportHeight, width, height)
	viewportWidth, viewportHeight = viewportSize(viewportWidth, viewportHeight)
	width = tonumber(width) or Layout.ReferenceWindowWidth
	height = tonumber(height) or Layout.ReferenceWindowHeight

	return round((viewportWidth - width) / 2), round((viewportHeight - height) / 2)
end

function Layout.GetPositionBounds(viewportWidth, viewportHeight, width, height)
	viewportWidth, viewportHeight = viewportSize(viewportWidth, viewportHeight)
	width = math.max(1, tonumber(width) or Layout.ReferenceWindowWidth)
	height = math.max(1, tonumber(height) or Layout.ReferenceWindowHeight)

	local margin = Layout.ViewportMargin
	local visibleWidth = math.min(width, math.max(64, Layout.MinimumVisibleWidth))
	local titleBarHeight = math.min(height, math.max(1, Layout.TitleBarHeight))
	local minimumX = margin - width + visibleWidth
	local maximumX = viewportWidth - margin - visibleWidth
	local minimumY = margin
	local maximumY = viewportHeight - margin - titleBarHeight

	if minimumX > maximumX then
		local centeredX = round((viewportWidth - width) / 2)
		minimumX = centeredX
		maximumX = centeredX
	end

	if minimumY > maximumY then
		local centeredY = round((viewportHeight - height) / 2)
		minimumY = centeredY
		maximumY = centeredY
	end

	return round(minimumX), round(minimumY), round(maximumX), round(maximumY)
end

function Layout.ClampPosition(viewportWidth, viewportHeight, width, height, x, y)
	local minimumX, minimumY, maximumX, maximumY =
		Layout.GetPositionBounds(viewportWidth, viewportHeight, width, height)

	return clamp(round(tonumber(x) or 0), minimumX, maximumX),
		clamp(round(tonumber(y) or 0), minimumY, maximumY)
end

function Layout.GetDraggedPosition(
	startX,
	startY,
	deltaX,
	deltaY,
	viewportWidth,
	viewportHeight,
	windowWidth,
	windowHeight
)
	local x = (tonumber(startX) or 0) + (tonumber(deltaX) or 0)
	local y = (tonumber(startY) or 0) + (tonumber(deltaY) or 0)

	if viewportWidth ~= nil and viewportHeight ~= nil and windowWidth ~= nil and windowHeight ~= nil then
		return Layout.ClampPosition(viewportWidth, viewportHeight, windowWidth, windowHeight, x, y)
	end

	return round(x), round(y)
end

function Layout.ScaleWindow(
	oldViewportWidth,
	oldViewportHeight,
	newViewportWidth,
	newViewportHeight,
	windowX,
	windowY,
	windowWidth,
	windowHeight,
	targetWidth,
	targetHeight
)
	oldViewportWidth, oldViewportHeight = viewportSize(oldViewportWidth, oldViewportHeight)
	newViewportWidth, newViewportHeight = viewportSize(newViewportWidth, newViewportHeight)
	windowX = tonumber(windowX) or 0
	windowY = tonumber(windowY) or 0
	windowWidth = tonumber(windowWidth) or Layout.ReferenceWindowWidth
	windowHeight = tonumber(windowHeight) or Layout.ReferenceWindowHeight

	local horizontalScale = newViewportWidth / oldViewportWidth
	local verticalScale = newViewportHeight / oldViewportHeight
	local contentScale = math.min(horizontalScale, verticalScale)
	local newWidth, newHeight = Layout.FitSize(
		newViewportWidth,
		newViewportHeight,
		tonumber(targetWidth) or windowWidth * contentScale,
		tonumber(targetHeight) or windowHeight * contentScale
	)
	local centerX = (windowX + windowWidth / 2) * horizontalScale
	local centerY = (windowY + windowHeight / 2) * verticalScale
	local newX = round(centerX - newWidth / 2)
	local newY = round(centerY - newHeight / 2)

	newX, newY = Layout.ClampPosition(newViewportWidth, newViewportHeight, newWidth, newHeight, newX, newY)
	return newX, newY, newWidth, newHeight
end

return Layout
