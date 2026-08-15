local Layout = {
	ReferenceViewportWidth = 1280,
	ReferenceViewportHeight = 720,
	ReferenceWindowWidth = 680,
	ReferenceWindowHeight = 380,
	MinimumWindowWidth = 500,
	MinimumWindowHeight = 280,
	MaximumWindowWidth = 840,
	MaximumWindowHeight = 500,
	ViewportMargin = 8,
}

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function round(value)
	return math.floor(value + 0.5)
end

local function usableViewport(width, height)
	width = math.max(1, tonumber(width) or Layout.ReferenceViewportWidth)
	height = math.max(1, tonumber(height) or Layout.ReferenceViewportHeight)

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
	viewportWidth = math.max(1, tonumber(viewportWidth) or Layout.ReferenceViewportWidth)
	viewportHeight = math.max(1, tonumber(viewportHeight) or Layout.ReferenceViewportHeight)

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
	return round(((tonumber(viewportWidth) or Layout.ReferenceViewportWidth) - width) / 2),
		round(((tonumber(viewportHeight) or Layout.ReferenceViewportHeight) - height) / 2)
end

function Layout.GetDraggedPosition(startX, startY, deltaX, deltaY)
	-- Dragging is deliberately unrestricted. A user may park the window partly
	-- or completely outside the viewport and bring it back with the same gesture.
	return round((tonumber(startX) or 0) + (tonumber(deltaX) or 0)),
		round((tonumber(startY) or 0) + (tonumber(deltaY) or 0))
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
	oldViewportWidth = math.max(1, tonumber(oldViewportWidth) or Layout.ReferenceViewportWidth)
	oldViewportHeight = math.max(1, tonumber(oldViewportHeight) or Layout.ReferenceViewportHeight)
	newViewportWidth = math.max(1, tonumber(newViewportWidth) or oldViewportWidth)
	newViewportHeight = math.max(1, tonumber(newViewportHeight) or oldViewportHeight)
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

	return round(centerX - newWidth / 2), round(centerY - newHeight / 2), newWidth, newHeight
end

return Layout
