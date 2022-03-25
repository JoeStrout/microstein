// 3D-ish rendering of walls, decorationss, and entities,
// using stretched sprites.

import "qa"
import "mathUtil"

// Handy constants
twoPi = pi * 2
halfPi = pi / 2
degToRad = pi / 180
radToDeg = 180 / pi

imageCache = {}
findImage = function(partialPath)
	if imageCache.hasIndex(partialPath) then return imageCache[partialPath]
	img = file.loadImage("/usr/" + partialPath)
	if not img then img = file.loadImage("/sys/" + partialPath)
	imageCache[partialPath] = img
	return img
end function

// Coordinate system:
// We'll work mainly in 2D, with map points represented as [x,y].
// (We'll call the vertical dimension Z, often omitted/ignored.)
// 1 unit is the width (and height) of 1 wall section.  Where
// z matters at all, the floor is at 0 and the ceiling is at 1.

// Camera: defines the current view point and angle, as well
// as parameters like field of view (fov) and distance limit.
// There is only one camera; this is a global object.
camera = {}
// camera.pos: position of the camera.  Note the z position;
// when this is < 0.5 the ceiling feels high, because the camera
// is less than half the way to the ceiling.  When it is close
// to 1, then the ceiling feels low and cramped.
camera.pos = [9.46, 3.43, 0.6]

// the forward direction, in degrees (-180 to 180) and radians
camera.angle = 148
camera.angleRad = camera.angle * degToRad
// half the horizontal field of view, in degrees (0 to 90) and radians
camera.halfFov = 22.5
camera.halfFovRad = camera.halfFov * degToRad

camera.setAngle = function(degrees)
	camera.angle = (degrees + 180) % 360 - 180
	if camera.angle < -180 then camera.angle = camera.angle + 360
	camera.angleRad = camera.angle * degToRad
end function	
camera.turn = function(degreesCCW)
	self.setAngle self.angle + degreesCCW
end function
camera.moveForward = function(dist)
	self.pos[0] = self.pos[0] + cos(self.angleRad) * dist
	self.pos[1] = self.pos[1] + sin(self.angleRad) * dist
end function
camera.moveRight = function(dist)
	self.pos[0] = self.pos[0] + sin(self.angleRad) * dist
	self.pos[1] = self.pos[1] - cos(self.angleRad) * dist
end function

// Calculate the angle (in radians) of the given point, 
// relative to the camera's forward direction.
camera.relativeAngle = function(point)
	ang = (atan(point[1] - self.pos[1], point[0] - self.pos[0]) - 
	   self.angleRad + pi) % twoPi - pi
	if ang < -pi then ang = ang + twoPi
	return ang
end function


// Renderer: holds all the data needed for rendering the scene.
Renderer = {}
Renderer.depthBuf = [0] * 960 // (actually a 1/depth buffer)
Renderer.depthBufWall = [null] * 960

// Make a Wall class.  A wall is represented by two ordered
// points: left and right (when viewed from the visible side).
Wall = {}
Wall.p = null // [left, right]
Wall.imageA = findImage("pics/textures/ToonBrickA.png")
Wall.imageB = findImage("pics/textures/ToonBrickB.png")
Wall.imageAshort = Wall.imageA.getImage(0, 0, Wall.imageA.width/10, Wall.imageA.height)
Wall.imageBshort = Wall.imageB.getImage(0, 0, Wall.imageB.width/10, Wall.imageB.height)
Wall.sprite = null
Wall.make = function(left, right)
	w = new Wall
	w.p = [left, right]
	w.sprite = new Sprite
	if mathUtil.distance(left, right) < 0.25 then
		if rnd < 0.5 then w.sprite.image = w.imageAshort else w.sprite.image = w.imageBshort
	else
		if rnd < 0.5 then w.sprite.image = w.imageA else w.sprite.image = w.imageB
	end if
	if left[0] == right[0] then w.sprite.tint = "#CCCCCC"
	return w
end function

// Calculate the angle of each endpoint, in radians (range -pi to pi),
// relative to the current viewpoint and angle.
// Store in self.angles, and the (shortest) angle span in self.angSpan.
Wall.calcAngles = function
	self.angles = [camera.relativeAngle(self.p[0]), camera.relativeAngle(self.p[1])]
	self.angSpan = self.angles[0] - self.angles[1]
end function

// Call this method when a wall extends beyond the left end of the screen.
// Give it a reference point somewhere on the screen (at refScreenX), and
// the corresponding point on the wall in world coordinates.  This method
// will then set self.x0 and self.invD0 so that the wall looks correct at
// the edge of the screen (by extrapolating way beyond it as needed).
Wall.extrapolateOnLeft = function(refScreenX, refWallPt)
	// First, calculate t (distance along wall from right to left)
	// and inverse-distance of where the wall intersects left
	// edge of screen, from the wall reference point.
	angRad = camera.angleRad + camera.halfFovRad // angle at screen edge
	screenEdgeWorld = [camera.pos[0] + cos(angRad)*10,
	   camera.pos[1] + sin(angRad)*10]  // a world position at screen edge
	t = mathUtil.lineIntersectProportion(refWallPt, self.p[0],
	  camera.pos, screenEdgeWorld)  // t along wall (ref->0) at screen edge
	posCut = mathUtil.lerp2d(refWallPt, self.p[0], t)  // wall pos at screen edge
	invDcut = 1 / mathUtil.distance(posCut, camera.pos)  // invD at screen edge
	// Now we know all about the point on the wall at the edge
	// of the screen, extrapolate to find a proper x0 and invD0.
	self.x0 = refScreenX - refScreenX * (1/t)
	refInvD1 = 1 / mathUtil.distance(refWallPt, camera.pos)
	self.invD0 = refInvD1 + (invDcut - refInvD1) * (1/t)
end function

// Call this method when a wall extends beyond the right end of the screen.
// Give it a reference point somewhere on the screen (at refScreenX), and
// the corresponding point on the wall in world coordinates.  This method
// will then set self.x1 and self.invD1 so that the wall looks correct at
// the edge of the screen (by extrapolating way beyond it as needed).
Wall.extrapolateOnRight = function(refScreenX, refWallPt)
	// First, calculate t (distance along wall from ref point to right)
	// and inverse-distance of where the wall intersects right
	// edge of screen.
	angRad = camera.angleRad - camera.halfFovRad // angle at screen edge
	screenEdgeWorld = [camera.pos[0] + cos(angRad)*10,
	   camera.pos[1] + sin(angRad)*10]  // a world position at screen edge
	t = mathUtil.lineIntersectProportion(refWallPt, self.p[1],
	  camera.pos, screenEdgeWorld)  // t along wall (0->1) at screen edge
	posCut = mathUtil.lerp2d(refWallPt, self.p[1], t)  // wall pos at screen edge
	invDcut = 1 / mathUtil.distance(posCut, camera.pos)  // invD of wall
	// Now we know all about the point on the wall at the edge
	// of the screen, extrapolate to find a proper x1 and invD1.
	self.x1 = refScreenX + (960 - refScreenX) * (1/t)
	refInvD1 = 1 / mathUtil.distance(refWallPt, camera.pos)
	self.invD1 = refInvD1 + (invDcut - refInvD1) * (1/t)		
end function

Wall.writeToDepthBuffer = function
	// Assumes that calcAngles has already been called.
	if self.angles[1] > camera.halfFovRad or self.angles[0] < -camera.halfFovRad then return // (out of view)
	// Find the start and end screen column.
	self.x0 = 480 - tan(self.angles[0])*1158  // (1158 ~= 480 / tan(halfFovRad))
	self.x1 = 480 - tan(self.angles[1])*1158
	
	cutOnLeft = self.angles[0] > camera.halfFovRad
	cutOnRight = self.angles[1] < -camera.halfFovRad
	if cutOnLeft and cutOnRight then
		// This wall is cut off on both sides.  Dang, what a pain.
		// Let's find a point in the wall at the middle of the screen.
		screenMidWorld = [camera.pos[0] + cos(camera.angleRad)*10,
		   camera.pos[1] + sin(camera.angleRad)*10]
		t = mathUtil.lineIntersectProportion(self.p[0], self.p[1],
		  camera.pos, screenMidWorld)  // t along wall (0->1) at screen midpoint
		posMid = mathUtil.lerp2d(self.p[0], self.p[1], t)  // wall pos at screen mid
		// OK, now we know where the wall is in the center of the screen.
		// Let's use this, and the intersection of each screen edge,
		// to compute where the off-screen wall ends should be.
		self.extrapolateOnLeft 480, posMid
		self.extrapolateOnRight 480, posMid
	else if cutOnLeft then
		// This wall is cut off on the left.  Let's compute exactly
		// where on the wall that screen intersection happens, and
		// deal with just the visible part.
		self.invD1 = 1 / mathUtil.distance(self.p[1], camera.pos)
		self.extrapolateOnLeft self.x1, self.p[1]
	else if cutOnRight then
		self.invD0 = 1 / mathUtil.distance(self.p[0], camera.pos)
		self.extrapolateOnRight self.x0, self.p[0]
	else
		// Easy case: wall is entirely on screen.
		self.invD0 = 1 / mathUtil.distance(self.p[0], camera.pos)
		self.invD1 = 1 / mathUtil.distance(self.p[1], camera.pos)
	end if
	
	self.x0 = round(self.x0)
	self.x1 = round(self.x1)
	
	self.invDmid = (self.invD0 + self.invD1) / 2
	invDstep = (self.invD1 - self.invD0) / (self.x1 - self.x0)
	invD = self.invD0
	for x in range(self.x0, self.x1)
		if x >= 0 and x < 960 then
			if Renderer.depthBuf[x] < invD then
				Renderer.depthBuf[x] = invD
				Renderer.depthBuf[x] = invD
				Renderer.depthBufWall[x] = self
			end if
		end if
		// to-do: skip ahead to X=0, rather than stepping there like this
		invD = invD + invDstep
	end for
end function

Wall.positionSprite = function
	sp = self.sprite
	sp.x = (self.x0 + self.x1)/2
	sp.y = 320
	h0 = 300 * self.invD0
	h1 = 300 * self.invD1
	sp.setCorners [[self.x0, sp.y-h0], [self.x1, sp.y-h1], 
	  [self.x1, sp.y+h1], [self.x0, sp.y+h0]]
end function

// Entity class: represents things that can move around
// in the game, and always faces the camera directly.
Entity = new Sprite
Entity.pos = [0,0]
Entity.calcAngle = function
	self.angle = camera.relativeAngle(self.pos)
	self.invD = 1 / mathUtil.distance(self.pos, camera.pos)
	self.visible = (self.angle < camera.halfFovRad and 
	  self.angle > -camera.halfFovRad)
end function
Entity.positionSprite = function
	self.x = 480 - tan(self.angle)*1158  // (1158 ~= 480 / tan(halfFovRad))
	self.y = 320
	self.scale = 5 * self.invD
end function
Entity.pushSprite = function
	self.positionSprite
	display(4).sprites.push self
end function

Renderer.entities = []

// Decoration class: something that lays flat, on the floor
// or ceiling.
Decoration = new Sprite
Decoration.pos = [0,0]  // position of the CENTER of the decoration
Decoration.init = function(pos, scale)
	self.pos = pos
	x = self.pos[0]
	y = self.pos[1]
	h = 0.5 * scale  // (half-width)
	self.cornerPos = [   // world position of each corner
	 [x-h, y-h],[x+h, y-h],[x+h, y+h],[x-h, y+h]]
	self.angles = [0]*4  // camera-relative angle of each corner
	self.screenPos = [[0,0],[0,0],[0,0],[0,0]]
end function

Decoration.make = function(imageName, position, scale=1)
	dec = new Decoration
	dec.image = findImage(imageName)
	dec.init position, scale
	Renderer.decorations.push dec
end function

Decoration.calcAngles = function
	self.angles[0] = camera.relativeAngle(self.cornerPos[0])
	self.angles[1] = camera.relativeAngle(self.cornerPos[1])
	self.angles[2] = camera.relativeAngle(self.cornerPos[2])
	self.angles[3] = camera.relativeAngle(self.cornerPos[3])
	anglesCopy = self.angles[:]
	anglesCopy.sort
	self.minAngle = anglesCopy[0]
	self.maxAngle = anglesCopy[3]
	self.visible = (self.maxAngle > -camera.halfFovRad and
	  self.minAngle < camera.halfFovRad)
	if self.minAngle < -halfPi and self.maxAngle > halfPi then self.visible = false
end function

Decoration.pushSprite = function
	midAngle = (self.minAngle + self.maxAngle)/2
	self.x = 480 - tan(midAngle)*1158
	self.y = 320
	h = -300 + 600 * self.pos[2]
	for i in [0,1,2,3]
		// calculate the (inverse) depth and x position
		// of each corner
		invD = 1 / mathUtil.distance(self.cornerPos[i], camera.pos)
		self.screenPos[i][0] = 480 - tan(self.angles[i])*1158
		self.screenPos[i][1] = self.y + h * invD
	end for
	self.setCorners self.screenPos	
	display(4).sprites.push self
end function

Renderer.decorations = []


// Make some helper methods to generate sets of walls.
makeLongWall = function(leftmost, rightmost)
	result = []
	if leftmost[0] == rightmost[0] then
		if leftmost[1] < rightmost[1] then
			for y in range(leftmost[1], rightmost[1]-1)
				result.push Wall.make([leftmost[0], y], [leftmost[0], y+1])
			end for
		else
			for y in range(rightmost[1], leftmost[1]-1)
				result.push Wall.make([leftmost[0], y+1], [leftmost[0], y])
			end for
		end if
	else if leftmost[1] == rightmost[1] then
		if leftmost[0] < rightmost[0] then
			for x in range(leftmost[0], rightmost[0]-1)
				result.push Wall.make([x, leftmost[1]], [x+1, leftmost[1]])
			end for
		else
			for x in range(rightmost[0], leftmost[0]-1)
				result.push Wall.make([x+1, leftmost[1]], [x, leftmost[1]])
			end for
		end if
	else
		qa.fail "walls must differ in only one dimension"
	end if
	return result
end function

// Make a box with the walls facing inward (e.g., for
// the outer walls of the map)
makeInwardBox = function(left, bottom, width, height)
	top = bottom + height
	right = left + width
	return makeLongWall([left,bottom], [left,top]) +
	makeLongWall([left,top], [right,top]) +
	makeLongWall([right,top], [right,bottom]) +
	makeLongWall([right,bottom], [left,bottom])
end function

// Make a box with the walls facing outward (a column or obstacle).
makeOutwardBox = function(left, bottom, width, height)
	top = bottom + height
	right = left + width
	return makeLongWall([left,top], [left,bottom]) +
	makeLongWall([right,top], [left,top]) +
	makeLongWall([right,bottom], [right,top]) +
	makeLongWall([left,bottom], [right,bottom])
end function


walls = []

Renderer.analyze = function	
	self.depthBuf = [0]*960
	self.depthBufWall = [null]*960
	// Let all decorations calculate their angles,
	// and gather up any that may be visible.
	self.visibleDecorations = []
	for d in self.decorations
		d.calcAngles
		if d.visible then self.visibleDecorations.push d
	end for
	
	// Find the walls within the viewing angle,	
	// AND potentially visible at all.
	// Write these to the depth buffer.
	maxAng = camera.halfFovRad
	minAng = -maxAng
	for w in walls
		w.visible = false
		w.calcAngles
		if w.angSpan <= 0 then continue // backside
		if w.angSpan > pi then continue // behind us
		if w.angles[0] < minAng or w.angles[1] > maxAng then continue // out of view
		w.writeToDepthBuffer
	end for
	// Then, prepare the list of visible walls, sorted by depth.
	self.visibleWalls = []
	lastWall = null
	for x in Renderer.depthBuf.indexes
		if not Renderer.depthBufWall[x] or Renderer.depthBuf[x] == 0 then continue
		if Renderer.depthBufWall[x] == lastWall then continue
		lastWall = Renderer.depthBufWall[x]
		if not lastWall.visible then
			lastWall.visible = true
			self.visibleWalls.push lastWall
		end if
	end for	
	self.visibleWalls.sort "invDmid"	
	// Analyze our entities too.
	self.visibleEntities = []
	for ent in self.entities
		ent.calcAngle
		if ent.visible then self.visibleEntities.push ent
	end for
	self.visibleEntities.sort "invD"
end function

Renderer.renderWithLines = function
	for x in Renderer.depthBuf.indexes
		if not Renderer.depthBufWall[x] or Renderer.depthBuf[x] == 0 then continue
		h = 300 * Renderer.depthBuf[x]
		gfx.line x, 150+h, x, 150-h, Renderer.depthBufWall[x].color
	end for	
end function

Renderer.render = function
	// Assume that Renderer.analyze has already been called.
	// So all we have to do is display the sprites for visible things.
	display(4).sprites = []
	
	// Render all decorations first.
	for d in self.visibleDecorations
		d.pushSprite
	end for
	
	// Then, render walls and entities, in depth order.
	entIdx = 0  // index into our visibleEntities list
	for wall in self.visibleWalls
		while entIdx < self.visibleEntities.len and
			self.visibleEntities[entIdx].invD < wall.invDmid
			self.visibleEntities[entIdx].pushSprite
			entIdx = entIdx + 1
		end while
		wall.positionSprite
		display(4).sprites.push wall.sprite
	end for	
	while entIdx < self.visibleEntities.len
		self.visibleEntities[entIdx].pushSprite
		entIdx = entIdx + 1
	end while
end function

rerender = function
	Renderer.analyze
	yield
	Renderer.render
end function

makeDemoMap = function
	// First let's define the map.
	outer.walls = makeInwardBox(0, 0, 10, 10)
	outer.walls = walls + makeOutwardBox(2, 3, 3, 2)
	outer.walls = walls + makeOutwardBox(7, 6, 2, 2)
	outer.walls = walls + makeOutwardBox(5, 8, 1, 1)

	// And throw in a Wumpus.
	wumpus = new Entity
	wumpus.image = findImage("pics/Wumpus.png")
	wumpus.pos = [6.5, 3.5, 0.5]
	Renderer.entities.push wumpus

	// And some decorations
	Decoration.make "pics/floorCobble1.png", [6.5, 3.5, 0], 0.25 + 0.5*rnd
	Decoration.make "pics/floorCobble2.png", [4.5, 2.5, 0], 0.25 + 0.5*rnd
	Decoration.make "pics/floorCobble3.png", [7.5, 6.5, 0], 0.25 + 0.5*rnd
end function

demo = function(makeMap=false)
	if makeMap then makeDemoMap
	clear

	gfx.fillRect 0, 0, 960, 320, color.silver	// floor
	gfx.fillRect 0, 320, 960, 320, color.gray	// ceiling

	rerender

	while true
		needRender = true
		alt = key.pressed("left alt") or key.pressed("right alt")
		if key.pressed("escape") then
			break
		else if key.pressed("left") then
			if alt then camera.moveRight -0.1 else camera.turn 4
		else if key.pressed("right") then
			if alt then camera.moveRight 0.1 else camera.turn -4
		else if key.pressed("up") then
			camera.moveForward 0.1
		else if key.pressed("down") then
			camera.moveForward -0.1
		else
			needRender = false
		end if
		if needRender then rerender
	end while

	key.clear
end function

if locals == globals then demo true
