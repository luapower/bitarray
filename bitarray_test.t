
setfenv(1, require'low')
require'bitarray'

local terra draw(a: bitarrview2d())
	for y=0,a.h do
		for x=0,a.w do
			pf('%c', iif(a:get(x, y), [('x'):byte()], [('_'):byte()]))
		end
		pfn('')
	end
end

local terra test_view2d()
	var a = bitarrview2d()

	var b: uint64 = 0xdeadbeef1badbeefULL
	var b0 = b
	a.bits = [&uint8](&b)
	a.stride = 16
	a.w = 16
	a.h = 4
	assert(a.w <= a.stride)
	assert(a.stride * a.h <= sizeof(b) * 8)
	--invert all bits one-by-one
	var aa = a:sub(0, 0, a.w, a.h)
	for y=0,aa.h do
		for x=0,aa.w do
			aa:set(x, y, not aa:get(x, y))
		end
	end
	assert(b == not b0)
	draw(aa)
end
test_view2d()

local terra test_view2d_graphic()

end
