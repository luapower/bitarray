--[[

	1-D and 2-D bit array type for Terra.
	Written by Cosmin Apreutesei. Public domain.

	A bit array is a packed array of bits.

]]

if not ... then require'bitarray_test'; return end

setfenv(1, require'low')
require'box2dlib'

local function view_type(size_t)

	local struct view {
		bits: &uint8;
		offset: size_t; --in bits, relative to &bits
		len: size_t; --in bits
	}

	view.empty = `view{bits = nil, offset = 0, len = 0}

	newcast(view, niltype, view.empty)

	view.metamethods.__apply = macro(function(self, i)
		return `self:get(i)
	end)

	addmethods(view, function()

		local addr = macro(function(self, i)
			return quote
				var i = i + self.offset
				in i >> 3, i and 7
			end
		end)

		terra view:get(i: size_t)
			assert(i >= 0 and i < self.len)
			var B, b = addr(self, i)
			return getbit(self.bits[B], b)
		end

		terra view:set(i: size_t, v: bool)
			assert(i >= 0 and i < self.len)
			var B, b = addr(self, i)
			setbit(self.bits[B], b, v)
		end

		terra view:sub(offset: size_t, len: size_t)
			offset = clamp(offset, 0, self.len-1)
			len = clamp(len, 0, self.len - offset)
			return view {bits = self.bits, offset = offset, len = len}
		end

		terra view:copy(dest: &view)
			var bits = min(self.len, dest.len)
			var offset1 = self.offset and 7 --offset in first byte
			if offset1 == (dest.offset and 7) then --alignments match
				var bits1 = min((8 - offset1) and 7, bits) --number of bits in first partial byte
				var bits2 = (bits - bits1) and 7 --number of bits in last partial byte
				var bytes = (bits - bits1) >> 3 --number of full bytes
				--copy first partial byte bit-by-bit
				for i = offset1, offset1 + bits1 do
					dest:set(i, self:get(i))
				end
				--copy in-between bytes in bulk
				copy(
					dest.bits + div_up(dest.offset, 8),
					self.bits + div_up(self.offset, 8),
					bytes)
				--copy last partial byte bit-by-bit
				var offset2 = [int](bits1 > 0) + (bytes << 3)
				for i = offset2, offset2 + bits2 do
					dest:set(i, self:get(i))
				end
			else --bit-by-bit copy
				for i=0,self.len do
					dest:set(i, self:get(i))
				end
			end
		end

		setinlined(view.methods, function(m) return m ~= 'copy' end)

	end)

	return view

end
view_type = memoize(view_type)

local view_type = function(size_t)
	if type(size_t) == 'table' then
		size_t = size_t.size_t
	end
	size_t = size_t or int
	return view_type(size_t)
end

low.bitarrview = macro(
	function(size_t)
		local view_type = view_type(size_t and size_t:astype())
		return `view_type(nil)
	end, view_type
)

--2D bitarray view (aka monochrome bitmap).

local function view_type(size_t)

	local struct view {
		bits: &uint8;
		offset: size_t; --in bits, relative to &bits
		stride: size_t; --in bits
		w: size_t; --in bits
		h: size_t; --in bits
	}

	view.empty = `view{bits = nil, offset = 0, stride = 0, w = 0, h = 0}

	newcast(view, niltype, view.empty)

	addmethods(view, function()

		local offset = macro(function(self, x, y)
			return `self.offset + y * self.stride + x
		end)

		local addr = macro(function(self, x, y)
			return quote
				var i = offset(self, x, y)
				in i >> 3, i and 7
			end
		end)

		terra view:get(x: size_t, y: size_t)
			assert(x >= 0 and x < self.w
				and y >= 0 and y < self.h)
			var B, b = addr(self, x, y)
			return getbit(self.bits[B], b)
		end

		terra view:set(x: size_t, y: size_t, v: bool)
			assert(x >= 0 and x < self.w
				and y >= 0 and y < self.h)
			var B, b = addr(self, x, y)
			setbit(self.bits[B], b, v)
		end

		--create a view representing a rectangular region inside this view.
		--the new view references the same buffer, nothing is copied.
		terra view:sub(x: size_t, y: size_t, w: size_t, h: size_t)
			x, y, w, h = box2d.intersect(x, y, w, h, 0, 0, self.w, self.h)
			return view {bits = self.bits, offset = offset(self, x, y),
				stride = self.stride, w = w, h = h}
		end

		--create a 1-D view of a line.
		terra view:line(y: size_t)
			var line = bitarrview(size_t)
			line.bits = self.bits
			line.offset = self.offset + y * self.stride
			line.len = self.w
			return line
		end

		terra view:copy(dest: &view)
			var sub: view
			if dest.w < self.w or dest.h < self.h then --self needs cropping
				sub = self:sub(0, 0, dest.w, dest.h)
				self = &sub
			end
			if self.stride == dest.stride
				and ((self.stride and 7) == 0)
				and ((self.offset and 7) == 0)
				and ((dest.offset and 7) == 0)
			then --strides match and rows are byte-aligned: copy whole.
				copy(
					dest.bits + (dest.offset << 3),
					self.bits + (self.offset << 3),
					self.h * (self.stride << 3))
			else --copy line-by-line
				var sline = self:line(0)
				var dline = dest:line(0)
				for i=0,self.h do
					sline:copy(&dline)
					inc(sline.offset, self.stride)
					inc(dline.offset, self.stride)
				end
			end
		end

		setinlined(view.methods)

	end)

	return view

end
view_type = memoize(view_type)

local view_type = function(size_t)
	if type(size_t) == 'table' then
		size_t = size_t.size_t
	end
	size_t = size_t or int
	return view_type(size_t)
end

low.bitarrview2d = macro(
	function(size_t)
		local view_type = view_type(size_t and size_t:astype())
		return `view_type(nil)
	end, view_type
)

--dynamically allocated 2D bitarray.

