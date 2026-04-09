-- https://github.com/TannerRogalsky/Stratcave/blob/master/Polygon.lua

function GenTriangles(polygon, vertices)
	local triangles = {} -- list of triangles to be returned
	local concave = {}   -- list of concave edges
	local adj = {}       -- vertex adjacencies

	-- retrieve adjacencies as the rest will be easier to implement
	for i,p in ipairs(vertices) do
		local l = (i == 1) and vertices[#vertices] or vertices[i-1]
		local r = (i == #vertices) and vertices[1] or vertices[i+1]
		adj[p] = {p = p, l = l, r = r} -- point, left and right neighbor
		-- test if vertex is a concave edge
		if not ccw(l,p,r) then concave[p] = p end
	end

	-- and ear is an edge of the polygon that contains no other
	-- vertex of the polygon
	local function isEar(p1,p2,p3)
		if not ccw(p1,p2,p3) then return false end
		for q,_ in pairs(concave) do
			if pointInTriangle(q, p1,p2,p3) then return false end
		end
		return true
	end

	-- main loop
	local nPoints, skipped = #vertices, 0
	local p = adj[ vertices[2] ]
	while nPoints > 3 do
		if not concave[p.p] and isEar(p.l, p.p, p.r) then
			triangles[#triangles+1] = {p.l, p.p, p.r}
			if concave[p.l] and ccw(adj[p.l].l, p.l, p.r) then
				concave[p.l] = nil
			end
			if concave[p.r] and ccw(p.l, p.r, adj[p.r].r) then
				concave[p.r] = nil
			end
			-- remove point from list
			adj[p.p] = nil
			adj[p.l].r = p.r
			adj[p.r].l = p.l
			nPoints = nPoints - 1
			skipped = 0
			p = adj[p.l]
		else
			p = adj[p.r]
			skipped = skipped + 1
			assert(skipped <= nPoints, "Cannot triangulate polygon (is the polygon intersecting itself?)")
		end
	end
	triangles[#triangles+1] = {p.l, p.p, p.r}

	return triangles
end

function ccw(p, q, r)
	return cross(p - q, r - p).z >= 0
end

function pointInTriangle(q, p1,p2,p3)
	local v1,v2 = p2 - p1, p3 - p1
	local qp = q - p1
	local dv = cross(v1, v2)
	local l = cross(qp, v2) / dv
	if l.z <= 0 then return false end
	local m = cross(v1, qp) / dv
	if m.z <= 0 then return false end
	return l.z+m.z < 1
end

function getIndexOfleftmost(vertices)
	local idx = 1
	for i = 2,#vertices do
		if vertices[i].x < vertices[idx].x then
			idx = i
		end
	end
	return idx
end

function TriangleArea(p1,p2,p3)
	local v1,v2 = p2 - p1, p3 - p1
	local dv = cross(v1, v2)

    return #dv/2;
end

function WeightedRandom(pool)
    local poolsize = 0
    for k, v in ipairs(pool) do
        if type(v[1]) == 'number' then
            poolsize = poolsize + tonumber(v[1])
        else
            return
        end
    end

    local selection = math.random(1, poolsize)

    for k, v in ipairs(pool) do
        selection = selection - v[1]
        if (selection <= 0) then
            return v[2]
        end
    end
end

function RandomPointInTriangle(triangle, percentMargin)
	percentMargin = percentMargin or 0
	local v1,v2 = triangle[2] - triangle[1], triangle[3] - triangle[1]

    local a, b = math.random() * (1 - 2*percentMargin) + percentMargin, math.random() * (1-2*percentMargin) + percentMargin
    if a + b > 1 then
        a = 1-a
        b = 1-b
    end

    return (a*v1 + b*v2) + triangle[1]
end