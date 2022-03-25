import "mazeGenerator"
import "microstein"

clear

mazeGenerator.generate
mazeGenerator.debugDraw

needsEndcap = function(col, row)
	// Return whether we have a standing wall that ends at this position,
	// not connected to any other wall, and so it needs a short endcap.
	// This is equivalent to: is there exactly one wall from this point?
	if col == 0 or col == mazeGenerator.kCols or 
	   row == 0 or row == mazeGenerator.kRows then return false	// (connects to outer wall)
	count = mazeGenerator.wall[col-1][row][1] +
			mazeGenerator.wall[col][row][1] +
			mazeGenerator.wall[col][row-1][0] +
			mazeGenerator.wall[col][row][0]
	return count == 1
end function	

microstein.walls = microstein.makeInwardBox(0, 0, mazeGenerator.kCols, mazeGenerator.kRows)
h = 0.05  // half wall thickness
for col in range(0, mazeGenerator.kCols-1)
	for row in range(0, mazeGenerator.kRows-1)
		if col > 0 and mazeGenerator.wall[col][row][0] then
			// vertical wall
			microstein.walls.push microstein.Wall.make([col+h, row-h], [col+h, row+1+h])
			microstein.walls.push microstein.Wall.make([col-h, row+1+h], [col-h, row-h])
			if needsEndcap(col, row) then
				microstein.walls.push microstein.Wall.make([col-h, row-h], [col+h, row-h])
			end if
			if needsEndcap(col, row+1) then
				microstein.walls.push microstein.Wall.make([col+h, row+1+h], [col-h, row+1+h])
			end if
		end if
		if row > 0 and mazeGenerator.wall[col][row][1] then
			// horizontal wall
			microstein.walls.push microstein.Wall.make([col-h, row-h], [col+1+h, row-h])
			microstein.walls.push microstein.Wall.make([col+1+h, row+h], [col-h, row+h])
			if needsEndcap(col, row) then
				microstein.walls.push microstein.Wall.make([col-h, row+h], [col-h, row-h])
			end if
			if needsEndcap(col+1, row) then
				microstein.walls.push microstein.Wall.make([col+1+h, row-h], [col+1+h, row+h])
			end if
		end if		
	end for
end for


microstein.demo
