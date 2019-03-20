using Swizzles.Properties
using Swizzles.WrapperArrays
using Swizzles.ArrayifiedArrays
using Swizzles.GeneratedArrays
using Swizzles.ExtrudedArrays
using Swizzles.ScalarArrays

using Base: checkbounds_indices, throw_boundserror, tail, dataids, unaliascopy, unalias
using Base.Iterators: reverse, repeated, countfrom, flatten, product, take, peel, EltypeUnknown
using Base.Broadcast: Broadcasted, BroadcastStyle, Style, DefaultArrayStyle, AbstractArrayStyle, Unknown, ArrayConflict
using Base.Broadcast: materialize, materialize!, instantiate, broadcastable, preprocess, _broadcast_getindex, combine_eltypes, broadcast_shape
using Base.FastMath: add_fast, mul_fast, min_fast, max_fast
using StaticArrays



struct SwizzledArray{T, N, Op, mask, Init<:AbstractArray, Arg<:AbstractArray} <: GeneratedArray{T, N}
    op::Op
    init::Init
    arg::Arg
    Base.@propagate_inbounds function SwizzledArray{T, N, Op, mask, Init, Arg}(op::Op, init::Init, arg::Arg) where {T, N, Op, mask, Init, Arg}
        @assert T isa Type
        @assert max(0, mask...) <= ndims(arg)
        @assert length(mask) == N
        #TODO assert mask is unique
        if op === nothing
            @boundscheck begin
                arg_keeps = keeps(arg)
                if any(imasktuple(d->kept(arg_keeps[d]), d->false, Val(mask), Val(ndims(arg))))
                    throw(DimensionMismatch("TODO"))
                end
            end
        end
        new(op, init, arg)
    end
end

@inline function SwizzledArray{T, N, Op, mask}(op::Op, init::Init, arg::Arg) where {T, N, Op, mask, Init, Arg}
    SwizzledArray{T, N, Op, mask, Init, Arg}(op, init, arg)
end

@inline function Base.convert(::Type{SwizzledArray{T}}, arr::SwizzledArray{S, N, Op, mask, Init, Arg}) where {T, S, N, Op, mask, Init, Arg}
    return SwizzledArray{T, N, Op, mask, Init, Arg}(arr.op, arr.init, arr.arg)
end

@inline function Properties.eltype_bound(arr::SwizzledArray)
    S = Properties.eltype_bound(arr.arg)
    if arr.op === nothing
        return S
    end
    T = Properties.eltype_bound(arr.init)
    T! = Union{T, Properties.return_type(arr.op, T, S)}
    if T! <: T
        return T!
    end
    arg_keeps = keeps(arr.arg)
    arr_mask = mask(arr)
    if all(imasktuple(d->arg_keeps[d] isa Extrude, d->true, Val(mask(arr)), Val(ndims(arr.arg))))
        return T!
    end
    T = T!
    T! = Union{T, Properties.return_type(arr.op, T, S)}
    if T! <: T
        return T!
    end
    return Any
end

@inline mask(::Type{<:SwizzledArray{<:Any, <:Any, <:Any, _mask}}) where {_mask} = _mask
@inline mask(::SwizzledArray{<:Any, <:Any, <:Any, _mask}) where {_mask} = _mask



function Base.show(io::IO, arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    print(io, SwizzledArray)
    print(io, "{$T, $N, $Op, $mask}($(arr.op), $(arr.init), $(arr.arg))")
    nothing
end

Base.parent(arr::SwizzledArray) = arr.arg
Base.parent(::Type{<:SwizzledArray{T, N, Op, mask, Init, Arg}}) where {T, N, Op, mask, Init, Arg} = Arg
WrapperArrays.iswrapper(arr::SwizzledArray) = true
function WrapperArrays.adopt(arg::Arg, arr::SwizzledArray{T, N, Op, mask, Init}) where {T, N, Op, mask, Init, Arg}
    SwizzledArray{T, N, Op, mask, Init, Arg}(arr.op, arr.init, arg)
end

Base.dataids(arr::SwizzledArray) = (dataids(arr.op), dataids(arr.init), dataids(arr.arg))
function Base.unaliascopy(arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    op = unaliascopy(arr.op)
    init = unaliascopy(arr.init)
    arg = unaliascopy(arr.arg)
    SwizzledArray{T, N, typeof(op), mask, typeof(init), typeof(arg)}(op, init, arg)
end
function Base.unalias(dst, arr::SwizzledArray{T, N, Op, mask}) where {T, N, Op, mask}
    op = unalias(dst, arr.op)
    init = unalias(dst, arr.init)
    arg = unalias(dst, arr.arg)
    SwizzledArray{T, N, typeof(op), mask, typeof(init), typeof(arg)}(op, init, arg)
end

@inline function Base.size(arr::SwizzledArray)
    arg_size = size(arr.arg)
    masktuple(d->1, d->arg_size[d], Val(mask(arr)))
end

@inline function Base.axes(arr::SwizzledArray)
    arg_axes = axes(arr.arg)
    masktuple(d->Base.OneTo(1), d->arg_axes[d], Val(mask(arr)))
end



Base.@propagate_inbounds function Base.copy(src::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{SubArray{T, <:Any, <:SwizzledArray{T, N}, <:Tuple{Vararg{Any, N}}}}}) where {T, N}
    return Base.copy(Broadcasted{DefaultArrayStyle{0}}(identity, (convert(SwizzledArray, src.args[1]),)))
end

Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray, src::Broadcasted{Nothing, <:Any, typeof(identity), <:Tuple{SubArray{T, <:Any, <:SwizzledArray{T, N}, <:Tuple{Vararg{Any, N}}}}}) where {T, N}
    #A view of a Swizzle can be computed as a swizzle of a view (hiding the
    #complexity of nilping view indices). Therefore, we convert first.
    return Base.copyto!(dst, convert(SwizzledArray, src.args[1]))
end

Base.@propagate_inbounds function Base.convert(::Type{SwizzledArray}, src::SubArray{T, M, Arr, <:Tuple{Vararg{Any, N}}}) where {T, N, M, Op, Arr <: SwizzledArray{T, N, Op}}
    arr = parent(src)
    inds = Base.parentindices(src)
    arg = arr.arg
    init = arr.init
    init′ = SubArray(init, ntuple(n -> (Base.@_inline_meta; size(init, n) == 1 ? firstindex(init, n) : inds[n]), Val(ndims(init))))
    inds′ = parentindex(arr, inds...)
    arg′ = SubArray(arg, inds′)
    mask′ = remask(inds, inds′, mask(arr))
    return SwizzledArray{eltype(src), M, Op, mask′}(arr.op, init′, arg′)
end

@inline function remask(inds, inds′, mask)
    _remask(map(Base.index_dimsum, inds), map(Base.index_dimsum, inds′), Val(mask))
end
@inline function remask(inds, inds′, mask::Tuple{})
    ()
end
@generated function _remask(inds, inds′, ::Val{mask}) where {mask}
    return quote
        Base.@_inline_meta
        $(__remask(map(i -> !(i <: Tuple{}), Tuple(inds.parameters)),
                   map(i -> !(i <: Tuple{}), Tuple(inds′.parameters)), mask))
    end
end
function __remask(inds, inds′, mask)
    if first(inds)
        if first(mask) === nil
            return (nil, __remask(Base.tail(inds), inds′, Base.tail(mask))...)
        else
            return (count(inds′[1:first(mask)]), __remask(Base.tail(inds), inds′, Base.tail(mask))...)
        end
    else
        return __remask(Base.tail(inds), inds′, Base.tail(mask))
    end
end
__remask(::Tuple{}, inds′, ::Tuple{}) = ()

Base.similar(::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{<:SwizzledArray{T}}}) where {T} = ScalarArray{T}()

Base.@propagate_inbounds function Base.copy(src::Broadcasted{DefaultArrayStyle{0}, <:Any, typeof(identity), <:Tuple{Arr}}) where {Arr <: SwizzledArray}
    arr = src.args[1]
    dst = similar(src)
    copyto!(dst, Broadcasted{Nothing}(identity, (arr,)))
    return dst[]
end

Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray, src::Broadcasted{Nothing, <:Any, typeof(identity), <:Tuple{SwizzledArray}})
    #This method gets called when the destination eltype is unsuitable for
    #accumulating the swizzle. Therefore, we should allocate a suitable
    #destination and then accumulate.
    arr = src.args[1]
    arr′ = copyto!(similar(arr), arr)
    @assert ndims(dst) == ndims(arr′)
    copyto!(dst, arr′)
end

is_nil_mask(mask) = mask == ntuple(n->nil, length(mask))
@generated function is_nil_mask(::Val{mask}) where {mask}
    return is_nil_mask(mask)
end

is_oneto_mask(mask) = mask == 1:length(mask)
@generated function is_oneto_mask(::Val{mask}) where {mask}
    return is_oneto_mask(mask)
end

Base.@propagate_inbounds function Base.copyto!(dst::AbstractArray{T, N}, src::Broadcasted{Nothing, <:Any, typeof(identity), Tuple{Arr}}) where {T, N, Arr <: SwizzledArray{<:T, N}}
    arr = src.args[1]
    op = arr.op
    if is_nil_mask(Val(mask(arr)))
        if op === nothing
            _swizzle_copyto_nilmask_noop!(dst, arr)
        else
            _swizzle_copyto_nilmask_op!(dst, arr)
        end
    elseif is_oneto_mask(Val(mask(arr)))
        if op === nothing
            _swizzle_copyto_onetomask_noop!(dst, arr)
        else
            _swizzle_copyto_onetomask_op!(dst, arr)
        end
    else
        if op === nothing
            _swizzle_copyto_anymask_noop!(dst, arr)
        else
            _swizzle_copyto_anymask_op!(dst, arr)
        end
    end
    return dst
end

Base.@propagate_inbounds function _swizzle_copyto_nilmask_noop!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    @inbounds loop(eachindex(arg)) do i
        Base.@_propagate_inbounds_meta
        dst[1] = arg[i]
        return nothing
    end
end

Base.@propagate_inbounds function _swizzle_copyto_nilmask_op!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    dst .= src.init
    @inbounds loop(eachindex(arg)) do i
        Base.@_propagate_inbounds_meta
        dst[1] = src.op(dst[1], arg[i])
        return nothing
    end
end

Base.@propagate_inbounds function _swizzle_copyto_onetomask_noop!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    @inbounds loop(eachindex(arg, dst)) do i
        Base.@_propagate_inbounds_meta
        dst[i] = arg[i]
        return nothing
    end
end

Base.@propagate_inbounds function _swizzle_copyto_onetomask_op!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    dst .= src.init
    @inbounds loop(eachindex(arg, dst)) do i
        Base.@_propagate_inbounds_meta
        dst[i] = src.op(dst[i], arg[i])
        return nothing
    end
end

Base.@propagate_inbounds function _swizzle_copyto_anymask_noop!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    inds = CartesianIndices(arg)
    @inbounds loop(eachindex(arg, inds)) do i
        Base.@_propagate_inbounds_meta
        i′ = childindex(src, inds[i])
        dst[i′...] = arg[i]
        return nothing
    end
end

Base.@propagate_inbounds function _swizzle_copyto_anymask_op!(dst, src)
    arg = ArrayifiedArrays.preprocess(dst, src.arg)
    dst .= src.init
    inds = CartesianIndices(arg)
    @inbounds loop(eachindex(arg, inds)) do i
        Base.@_propagate_inbounds_meta
        i′ = childindex(src, inds[i])
        dst[i′...] = src.op(dst[i′...], arg[i])
        return nothing
    end
end



Base.@propagate_inbounds function parentindex(arr::SubArray, i...)
    return Base.reindex(Base.parentindices(arr), i)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray, i::Integer)
    return parentindex(arr, CartesianIndices(arr)[i])
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray, i::CartesianIndex)
    return parentindex(arr, Tuple(i)...)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray{<:Any, 1}, i::Integer)
    return invoke(parentindex, Tuple{typeof(arr), Any}, arr, i)
end

Base.@propagate_inbounds function parentindex(arr::SwizzledArray{<:Any, N}, i::Vararg{Any, N}) where {N}
    arg_axes = axes(arr.arg)
    imasktuple(d->Base.Slice(arg_axes[d]), d->i[d], Val(mask(arr)), Val(ndims(arr.arg)))
end


"""
   parentindex(arr, i)

   For all wrapper arrays arr such that `arr` involves an index remapping,
   return the indices into `parent(arr)` which affect the indices `i` of `arr`.

   See also: [`swizzle`](@ref).
"""
parentindex

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N}, i::Integer) where {N}
    return childindex(arr, CartesianIndices(arr.arg)[i])
end

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N}, i::CartesianIndex) where {N}
    return childindex(arr, Tuple(i)...)
end

Base.@propagate_inbounds function childindex(arr::SwizzledArray{<:Any, N, <:Any, <:Any, <:AbstractArray, <:AbstractArray{<:Any, M}}, i::Vararg{Integer, M}) where {N, M}
    masktuple(d->1, d->i[d], Val(mask(arr)))
end

"""
   childindex(arr, i)

   For all wrapper arrays arr such that `arr` involves an index remapping,
   return the indices into `arr` which affect the indices `i` of `parent(arr)`.

   See also: [`swizzle`](@ref).
"""
childindex


#function Base.Broadcast.preprocess(dest, arr::SwizzledArray{T, N, Op, mask, Arg}) where {T, N, Arg, Op, mask}
#    arg = preprocess(dest, arr.arg)
#    SwizzledArray{T, N, Op, mask, typeof(arg)}(arr.op, arg)
#end

"""
    `childstyle(::Type{<:AbstractArray}, ::BroadcastStyle)`

Broadcast styles are used to determine behavior of objects under broadcasting.
To customize the broadcasting behavior of a wrapper array, one can first declare
how the broadcast style should behave under broadcasting after the wrapper array
is applied by overriding the `childstyle` method.
"""
@inline childstyle(Arr::Type{<:AbstractArray}, ::BroadcastStyle) = BroadcastStyle(Arr)

@inline childstyle(Arr::Type{<:SwizzledArray}, ::DefaultArrayStyle) = DefaultArrayStyle{ndims(Arr)}()
@inline childstyle(Arr::Type{<:SwizzledArray}, ::BroadcastStyle) = DefaultArrayStyle{ndims(Arr)}()
@inline childstyle(::Type{<:SwizzledArray}, ::ArrayConflict) = ArrayConflict()
@inline childstyle(Arr::Type{<:SwizzledArray}, ::Style{Tuple}) = mask(Arr) == (1,) ? Style{Tuple}() : DefaultArrayStyle{ndims(Arr)}()

@inline function Broadcast.BroadcastStyle(Arr::Type{<:SwizzledArray})
    childstyle(Arr, BroadcastStyle(parent(Arr)))
end

@inline function Swizzles.ExtrudedArrays.keeps(arr::SwizzledArray)
    arg_keeps = keeps(arr.arg)
    arr_keeps = masktuple(d->Extrude(), d->arg_keeps[d], Val(mask(arr)))
    init_keeps = keeps(arr.init)
    return combinetuple(|, arr_keeps, init_keeps)
end

#=
function Swizzles.ExtrudedArrays.inferkeeps(Arr::Type{<:SwizzledArray})
    arg_keeps = inferkeeps(parent(Arr))
    masktuple(d->Extrude(), d->arg_keeps[d], Val(mask(Arr)))
end
=#

function Swizzles.ExtrudedArrays.lift_keeps(arr::SwizzledArray)
    return adopt(arrayify(lift_keeps(parent(arr))), arr)
end
